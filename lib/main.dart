import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  }
  runApp(const LeaderToolkitApp());
}

class LeaderToolkitApp extends StatelessWidget {
  const LeaderToolkitApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Leader Toolkit',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1769AA)),
          scaffoldBackgroundColor: const Color(0xFFF4F7FB),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        home: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty
            ? const _SetupPage()
            : const _AuthGate(),
      );
}

class _SetupPage extends StatelessWidget {
  const _SetupPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Konfigurasi Supabase belum tersedia. Build dengan SUPABASE_URL dan SUPABASE_ANON_KEY.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, _) => Supabase.instance.client.auth.currentSession == null
            ? const _LoginPage()
            : const _HomePage(),
      );
}

class _LoginPage extends StatefulWidget {
  const _LoginPage();
  @override
  State<_LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<_LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(), password: _password.text,
      );
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Gagal masuk: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() { _email.dispose(); _password.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const Icon(Icons.factory_outlined, size: 56),
                    const SizedBox(height: 12),
                    Text('Leader Toolkit', textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) => v == null || !v.contains('@') ? 'Masukkan email yang valid.' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      validator: (v) => v == null || v.isEmpty ? 'Password wajib diisi.' : null,
                      onFieldSubmitted: (_) => _signIn(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _signIn,
                      child: Text(_busy ? 'Memproses...' : 'Masuk'),
                    ),
                    const SizedBox(height: 8),
                    const Text('Akun dibuat oleh administrator Supabase.', textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _HomePage extends StatefulWidget {
  const _HomePage();
  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  final _db = Supabase.instance.client;
  int _tab = 0;
  String? _role;
  String? _profileError;

  bool get _isLeader => _role == 'leader';

  @override
  void initState() { super.initState(); _loadProfile(); }

  Future<void> _loadProfile() async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) throw const AuthException('Sesi login berakhir.');
      final row = await _db.from('profiles').select('role').eq('id', user.id).single();
      if (mounted) setState(() => _role = row['role'] as String? ?? 'supervisor');
    } catch (e) {
      if (mounted) setState(() => _profileError = 'Profil Supabase belum tersedia atau tidak dapat dibaca. Pastikan baris profiles memiliki UUID pengguna yang sama. ($e)');
    }
  }

  Future<void> _notify(Future<void> Function() action) async {
    try { await action(); }
    catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _edit(String table, {Map<String, dynamic>? row}) async {
    if (!_isLeader) return;
    final isOperator = table == 'operators';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RecordDialog(isOperator: isOperator, row: row),
    );
    if (result == null) return;
    await _notify(() async {
      if (row == null) {
        await _db.from(table).insert(result);
      } else {
        await _db.from(table).update(result).eq('id', row['id']);
      }
    });
  }

  Future<void> _delete(String table, Map<String, dynamic> row) async {
    if (!_isLeader) return;
    final name = row['name'] ?? row['style_name'] ?? 'data ini';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus data?'),
        content: Text('Hapus "$name"? Tindakan ini tidak dapat dibatalkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (confirmed == true) {
      await _notify(() async => _db.from(table).delete().eq('id', row['id']));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_profileError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Leader Toolkit')),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_profileError!))),
      );
    }
    if (_role == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final pages = [
      _Dashboard(db: _db),
      _DataList(db: _db, table: 'operators', isOperator: true, isLeader: _isLeader,
          onEdit: (row) => _edit('operators', row: row), onDelete: (row) => _delete('operators', row)),
      _DataList(db: _db, table: 'production_entries', isOperator: false, isLeader: _isLeader,
          onEdit: (row) => _edit('production_entries', row: row), onDelete: (row) => _delete('production_entries', row)),
      _AiPage(db: _db),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Leader Toolkit • ${_isLeader ? 'Leader' : 'Supervisor'}'),
        actions: [
          IconButton(tooltip: 'Keluar', onPressed: () => _notify(() => _db.auth.signOut()), icon: const Icon(Icons.logout)),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      floatingActionButton: _isLeader && (_tab == 1 || _tab == 2)
          ? FloatingActionButton.extended(
              onPressed: () => _edit(_tab == 1 ? 'operators' : 'production_entries'),
              icon: const Icon(Icons.add),
              label: Text(_tab == 1 ? 'Tambah operator' : 'Catat produksi'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Ringkasan'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'Operator'),
          NavigationDestination(icon: Icon(Icons.factory_outlined), label: 'Produksi'),
          NavigationDestination(icon: Icon(Icons.lightbulb_outline), label: 'AI'),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.db});
  final SupabaseClient db;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: db.from('production_entries').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? [];
          final target = rows.fold<int>(0, (s, r) => s + ((r['target'] as num?)?.toInt() ?? 0));
          final actual = rows.fold<int>(0, (s, r) => s + ((r['actual'] as num?)?.toInt() ?? 0));
          final achievement = target == 0 ? 0.0 : actual * 100 / target;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Ringkasan produksi', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _Metric('Catatan', '${rows.length}', Icons.receipt_long),
                _Metric('Target', '$target pcs', Icons.flag),
                _Metric('Aktual', '$actual pcs', Icons.check_circle_outline),
                _Metric('Pencapaian', '${achievement.toStringAsFixed(0)}%', Icons.trending_up),
              ]),
              if (snapshot.hasError) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Gagal memuat produksi: ${snapshot.error}')),
              if (rows.isEmpty && snapshot.connectionState == ConnectionState.waiting) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              ...rows.map((r) => Card(child: ListTile(
                title: Text('${r['style_name']} • ${r['process']}'),
                subtitle: Text('${r['line_name']} • ${r['actual']} / ${r['target']} pcs • defect ${r['defects'] ?? 0}'),
                trailing: Text('${r['created_at']}'.toString().split('T').first),
              ))),
            ],
          );
        },
      );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: (MediaQuery.sizeOf(context).width - 42) / 2,
    child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon), const SizedBox(height: 8), Text(label),
      Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
    ]))),
  );
}

class _DataList extends StatelessWidget {
  const _DataList({required this.db, required this.table, required this.isOperator, required this.isLeader, required this.onEdit, required this.onDelete});
  final SupabaseClient db;
  final String table;
  final bool isOperator, isLeader;
  final ValueChanged<Map<String, dynamic>> onEdit, onDelete;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: isOperator
        ? db.from(table).stream(primaryKey: ['id']).order('name')
        : db.from(table).stream(primaryKey: ['id']).order('created_at', ascending: false),
    builder: (context, snapshot) {
      final rows = snapshot.data ?? [];
      return ListView(padding: const EdgeInsets.all(16), children: [
        Text(isOperator ? 'Operator dan skill' : 'Produksi, proses dan target', style: Theme.of(context).textTheme.headlineSmall),
        if (snapshot.hasError) Text('Gagal memuat data: ${snapshot.error}'),
        if (rows.isEmpty && !snapshot.hasError) const Padding(padding: EdgeInsets.only(top: 16), child: Text('Belum ada data.')),
        ...rows.map((row) => Card(child: ListTile(
          title: Text(isOperator ? '${row['name']}' : '${row['style_name']} • ${row['process']}'),
          subtitle: Text(isOperator
              ? '${row['line_name']} • ${row['main_process']}\nSkill: ${jsonEncode(row['skills'] ?? [])}'
              : '${row['line_name']} • aktual ${row['actual']} / ${row['target']} • defect ${row['defects'] ?? 0} • downtime ${row['downtime_minutes'] ?? 0} menit'),
          isThreeLine: true,
          trailing: isLeader ? PopupMenuButton<String>(
            onSelected: (action) => action == 'edit' ? onEdit(row) : onDelete(row),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Hapus')),
            ],
          ) : null,
        ))),
      ]);
    },
  );
}

class _RecordDialog extends StatefulWidget {
  const _RecordDialog({required this.isOperator, this.row});
  final bool isOperator;
  final Map<String, dynamic>? row;
  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  static const _operatorFields = ['name', 'line_name', 'main_process', 'skills'];
  static const _productionFields = ['style_name', 'process', 'line_name', 'target', 'actual', 'defects', 'downtime_minutes'];

  List<String> get _names => widget.isOperator ? _operatorFields : _productionFields;

  @override
  void initState() {
    super.initState();
    _fields = {for (final name in _names) name: TextEditingController(text: _initial(name))};
  }

  String _initial(String name) {
    final value = widget.row?[name];
    if (name == 'skills' && value is List) {
      return value.map((s) => '${s['process']}: ${s['level']}').join('\n');
    }
    if (value != null) return '$value';
    return const {'actual': '0', 'defects': '0', 'downtime_minutes': '0'}[name] ?? '';
  }

  @override
  void dispose() { for (final c in _fields.values) { c.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.isOperator
        ? (widget.row == null ? 'Tambah operator' : 'Edit operator')
        : (widget.row == null ? 'Catat produksi' : 'Edit produksi')),
    content: SizedBox(width: 440, child: Form(key: _formKey, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      for (final name in _names) Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: _fields[name],
          keyboardType: _isNumeric(name) ? TextInputType.number : TextInputType.text,
          minLines: name == 'skills' ? 3 : 1,
          maxLines: name == 'skills' ? 5 : 1,
          decoration: InputDecoration(labelText: _label(name), hintText: name == 'skills' ? 'Obras: 3' : null),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (!_isOptional(name) && text.isEmpty) return 'Wajib diisi.';
            if (_isNumeric(name)) {
              final n = int.tryParse(text);
              if (n == null || n < (name == 'target' ? 1 : 0)) return 'Masukkan angka yang valid.';
            }
            return null;
          },
        ),
      ),
    ])))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
      FilledButton(onPressed: () {
        if (!_formKey.currentState!.validate()) return;
        final data = <String, dynamic>{};
        for (final name in _names) {
          final value = _fields[name]!.text.trim();
          if (name == 'skills') {
            data[name] = value.split('\n').where((s) => s.trim().isNotEmpty).map((line) {
              final parts = line.split(':');
              final level = int.tryParse(parts.length > 1 ? parts.last.trim() : '1') ?? 1;
              return {'process': parts.first.trim(), 'level': level.clamp(1, 5)};
            }).toList();
          } else if (_isNumeric(name)) {
            data[name] = int.parse(value);
          } else {
            data[name] = value;
          }
        }
        if (!widget.isOperator && widget.row == null) {
          data['recorded_by'] = Supabase.instance.client.auth.currentUser!.id;
        }
        Navigator.pop(context, data);
      }, child: const Text('Simpan')),
    ],
  );

  bool _isNumeric(String name) => const {'target', 'actual', 'defects', 'downtime_minutes'}.contains(name);
  bool _isOptional(String name) => name == 'skills' || name == 'actual' || name == 'defects' || name == 'downtime_minutes';
  String _label(String name) => const {
    'name': 'Nama operator', 'line_name': 'Line', 'main_process': 'Proses utama', 'skills': 'Skill per baris (proses: level)',
    'style_name': 'Style', 'process': 'Proses', 'target': 'Target pcs', 'actual': 'Aktual pcs', 'defects': 'Defect pcs', 'downtime_minutes': 'Downtime menit',
  }[name]!;
}

class _AiPage extends StatefulWidget {
  const _AiPage({required this.db});
  final SupabaseClient db;
  @override
  State<_AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<_AiPage> {
  bool _busy = false;
  String _answer = 'Jalankan analisis untuk mendapatkan ringkasan produksi.';

  Future<void> _analyze() async {
    if (_apiBaseUrl.isEmpty) { setState(() => _answer = 'API_BASE_URL belum diatur pada build.'); return; }
    setState(() { _busy = true; _answer = ''; });
    try {
      final token = widget.db.auth.currentSession?.accessToken;
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/v1/ai/analyze'),
        headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'},
        body: jsonEncode({'question': 'Analisis bottleneck produksi sewing dan berikan tindakan prioritas.'}),
      ).timeout(const Duration(seconds: 45));
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Backend ${response.statusCode}: ${response.body}');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      setState(() => _answer = data['analysis']?.toString() ?? 'Tidak ada hasil analisis.');
    } catch (e) {
      setState(() => _answer = 'Analisis gagal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Text('AI problem solving', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 8),
    const Text('Rekomendasi adalah bantuan analisis, bukan bukti sebab-akibat. Validasi kondisi di lantai produksi.'),
    const SizedBox(height: 12),
    FilledButton.icon(onPressed: _busy ? null : _analyze, icon: const Icon(Icons.auto_awesome), label: Text(_busy ? 'Menganalisis...' : 'Analisis produksi')),
    const SizedBox(height: 12),
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_answer))),
  ]);
}
