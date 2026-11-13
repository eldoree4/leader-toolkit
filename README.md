# Leader Toolkit

Flutter Android app for garment sewing production with Supabase authentication/realtime data, role-based permissions, AI-assisted process analysis, and Excel/PDF export.

## Setup

1. Create a Supabase project.
2. Run `backend/supabase/schema.sql` in the Supabase SQL editor. If rerunning, review existing policies and publication entries first.
3. Create Auth users in Supabase Dashboard. Add a row per user to `public.profiles` with the same Auth UUID and role `leader` or `supervisor`.
4. Install Flutter and run:

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY \
  --dart-define=API_BASE_URL=https://YOUR_API_HOST
```

The app signs in with Supabase Auth. Both roles can view realtime production/operator data. Only `leader` can create, edit, or delete records through RLS.

## Backend AI API

Set server-only environment variables; never put them in Flutter:

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export SUPABASE_URL=https://YOUR_PROJECT.supabase.co
export SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
export OPENAI_API_KEY=YOUR_SERVER_SIDE_OPENAI_KEY  # optional
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Health check: `GET /health`; protected analysis endpoint: `POST /v1/ai/analyze` (requires Supabase bearer access token).

## Excel/PDF

Use the export buttons in the app bar. Excel contains operator/skill and production sheets. PDF contains production summary.

## APK release through GitHub Actions

Repository secret/variable setup:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `API_BASE_URL`

Push to `main` or run GitHub Actions. The workflow uploads the APK artifact.
