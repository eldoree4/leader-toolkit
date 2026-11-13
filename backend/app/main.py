import json
import os
from typing import Any

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field
from supabase import Client, create_client

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")

app = FastAPI(title="Leader Toolkit API", version="1.0.0")


class AnalyzeRequest(BaseModel):
    question: str = Field(
        default="Analisis bottleneck produksi dan beri rekomendasi.",
        max_length=2000,
    )


def authenticated_client(
    authorization: str | None = Header(default=None),
) -> tuple[Client, dict[str, Any]]:
    """Validasi token Supabase dan baca data memakai hak akses pengguna."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Bearer token diperlukan")

    if not SUPABASE_URL or not SUPABASE_ANON_KEY:
        raise HTTPException(
            status_code=503,
            detail="Konfigurasi Supabase backend belum tersedia",
        )

    token = authorization.split(" ", 1)[1].strip()
    client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)

    try:
        user_response = client.auth.get_user(token)
        user = user_response.user
        if user is None:
            raise ValueError("Pengguna tidak ditemukan")

        # Query selanjutnya menggunakan JWT pengguna, bukan service-role key.
        client.postgrest.auth(token)
        profile = (
            client.table("profiles")
            .select("role")
            .eq("id", user.id)
            .single()
            .execute()
            .data
        )

        if not profile:
            raise HTTPException(
                status_code=403,
                detail="Profil pengguna belum dibuat",
            )

        return client, {"user_id": user.id, "role": profile["role"]}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=401,
            detail="Token tidak valid atau kedaluwarsa",
        ) from exc


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "leader-toolkit-api"}


@app.post("/v1/ai/analyze")
def analyze(
    payload: AnalyzeRequest,
    auth: tuple[Client, dict[str, Any]] = Depends(authenticated_client),
) -> dict[str, Any]:
    client, identity = auth

    try:
        # Nama operator tidak dikirim ke penyedia AI; yang dikirim hanya skill.
        operators = (
            client.table("operators")
            .select("line_name,main_process,skills")
            .limit(500)
            .execute()
            .data
            or []
        )
        production = (
            client.table("production_entries")
            .select(
                "style_name,process,line_name,target,actual,"
                "defects,downtime_minutes,created_at"
            )
            .order("created_at", desc=True)
            .limit(200)
            .execute()
            .data
            or []
        )
    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail="Gagal membaca data produksi",
        ) from exc

    facts = []
    for row in production:
        target = max(int(row.get("target") or 0), 0)
        actual = max(int(row.get("actual") or 0), 0)
        facts.append({
            **row,
            "achievement_pct": round(actual * 100 / target, 1) if target else 0,
        })

    if OPENAI_API_KEY:
        system_prompt = (
            "Anda adalah asisten peningkatan produksi sewing garmen yang berhati-hati. "
            "Jawab dalam Bahasa Indonesia. Pisahkan temuan dari hipotesis, jangan "
            "menganggap korelasi sebagai sebab pasti. Berikan pertanyaan validasi "
            "di lantai produksi dan tindakan prioritas yang aman."
        )
        user_payload = {
            "question": payload.question,
            "operators": operators,
            "production": facts,
        }

        try:
            with httpx.Client(timeout=40) as http:
                response = http.post(
                    "https://api.openai.com/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {OPENAI_API_KEY}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": OPENAI_MODEL,
                        "temperature": 0.2,
                        "messages": [
                            {"role": "system", "content": system_prompt},
                            {
                                "role": "user",
                                "content": json.dumps(
                                    user_payload,
                                    ensure_ascii=False,
                                ),
                            },
                        ],
                    },
                )
                response.raise_for_status()
                answer = response.json()["choices"][0]["message"]["content"]
                return {
                    "analysis": answer,
                    "source": "llm",
                    "generated_for": identity["role"],
                }
        except Exception:
            # Jika layanan AI gagal, lanjutkan dengan analisis aturan lokal.
            pass

    below_target = sorted(
        (row for row in facts if row["achievement_pct"] < 90),
        key=lambda row: row["achievement_pct"],
    )

    if not below_target:
        answer = (
            "Belum ada catatan di bawah 90% target pada data terbaru. "
            "Pastikan periode, output, defect, dan downtime tercatat lengkap."
        )
    else:
        findings = [
            (
                f"{row['style_name']} / {row['process']} di {row['line_name']}: "
                f"{row['actual']} dari target {row['target']} "
                f"({row['achievement_pct']}%); defect {row.get('defects', 0)}, "
                f"downtime {row.get('downtime_minutes', 0)} menit."
            )
            for row in below_target[:5]
        ]
        answer = (
            "Temuan prioritas:\n- "
            + "\n- ".join(findings)
            + "\n\nValidasi di lapangan: cek mesin/setup, material, kualitas, "
            "metode kerja, downtime, dan keseimbangan beban proses. Catat penyebab "
            "yang ditemukan, lakukan perbaikan terukur, lalu bandingkan output "
            "pada interval berikutnya. Insight ini bukan bukti sebab-akibat."
        )

    return {
        "analysis": answer,
        "source": "rules_fallback",
        "generated_for": identity["role"],
    }
