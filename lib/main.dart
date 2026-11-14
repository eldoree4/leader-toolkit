import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_supabaseUrl.isNotEmpty && _publishableKey.isNotEmpty) {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _publishableKey,
    );
  }

  runApp(const LeaderToolkitApp());
}

class LeaderToolkitApp extends StatelessWidget {
  const LeaderToolkitApp({super.key});

  @override
  Widget build(BuildContext context) {
    final configured = _supabaseUrl.isNotEmpty && _publishableKey.isNotEmpty;

    return MaterialApp(
      title: 'Leader Toolkit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1769AA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: configured ? const _AuthGate() : const _SetupPage(),
    );
  }
}

class _SetupPage extends StatelessWidget {
  const _SetupPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Konfigurasi Supabase belum tersedia. '
            'Atur SUPABASE_URL dan SUPABASE_PUBLISHABLE_KEY saat build.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (Supabase.instance.client.auth.currentSession == null) {
          return const _LoginPage();
        }
        return const _HomePage();
      },
    );
  }
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

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Gagal masuk: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  Text(
                    'Leader Toolkit',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (value) {
                      if (value == null || !value.contains('@')) {
                        return 'Masukkan email yang valid.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password wajib diisi.';
                      }
                      return null;
                    },
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
                  const Text(
                    'Akun harus dibuat oleh administrator Supabase.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  final _db = Supabase.instance.client;
  late final Future<Map<String, dynamic>> _profileFuture;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<Map<String, dynamic>> _loadProfile() async {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Sesi login tidak ditemukan.');

    return _db
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .single();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }

  Future<void> _editRecord(
    String table, {
    Map<String, dynamic>? row,
  }) async {
    final isOperator = table == 'operators';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RecordDialog(isOperator: isOperator, row: row),
    );

    if (result == null) return;

    await _run(() async {
      if (row == null) {
        await _db.from(table).insert(result);
      } else {
        await _db.from(table).update(result).eq('id', row['id']);
      }
    });
  }

  Future<void> _deleteRecord(
    String table,
    Map<String, dynamic> row,
  ) async {
    final label = row['name'] ?? row['style_name'] ?? 'data ini';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus data?'),
        content: Text('Hapus "$label"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _run(() async {
        await _db.from(table).delete().eq('id', row['id']);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Leader Toolkit')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Profil pengguna tidak ditemukan. Buat baris di tabel '
                  'profiles dengan UUID Auth pengguna yang sama.\n\n'
                  '${snapshot.error}',
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = snapshot.data!['role'] as String? ?? 'supervisor';
        final isLeader = role == 'leader';

        final pages = <Widget>[
          _Dashboard(db: _db),
          _DataList(
            db: _db,
            table: 'operators',
            isOperator: true,
            isLeader: isLeader,
            onEdit: (row) => _editRecord('operators', row: row),
            onDelete: (row) => _deleteRecord('operators', row),
          ),
          _DataList(
            db: _db,
            table: 'production_entries',
            isOperator: false,
            isLeader: isLeader,
            onEdit: (row) => _editRecord('production_entries', row: row),
            onDelete: (row) => _deleteRecord('production_entries', row),
          ),
          _AiPage(db: _db),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text('Leader Toolkit • ${isLeader ? 'Leader' : 'Supervisor'}'),
            actions: [
              IconButton(
                tooltip: 'Keluar',
                onPressed: () => _run(_db.auth.signOut),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: IndexedStack(index: _tab, children: pages),
          floatingActionButton: isLeader && (_tab == 1 || _tab == 2)
              ? FloatingActionButton.extended(
                  onPressed: () => _editRecord(
                    _tab == 1 ? 'operators' : 'production_entries',
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(
                    _tab == 1 ? 'Tambah operator' : 'Catat produksi',
                  ),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (index) => setState(() => _tab = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                label: 'Ringkasan',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                label: 'Operator',
              ),
              NavigationDestination(
                icon: Icon(Icons.factory_outlined),
                label: 'Produksi',
              ),
              NavigationDestination(
                icon: Icon(Icons.lightbulb_outline),
                label: 'AI',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.db});

  final SupabaseClient db;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: db
          .from('production_entries')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? [];
        final target = rows.fold<int>(
          0,
          (sum, row) => sum + ((row['target'] as num?)?.toInt() ?? 0),
        );
        final actual = rows.fold<int>(
          0,
          (sum, row) => sum + ((row['actual'] as num?)?.toInt() ?? 0),
        );
        final achievement = target == 0 ? 0.0 : actual * 100 / target;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Ringkasan produksi',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricCard('Catatan', '${rows.length}', Icons.receipt_long),
                _MetricCard('Target', '$target pcs', Icons.flag),
                _MetricCard('Aktual', '$actual pcs', Icons.check_circle_outline),
                _MetricCard(
                  'Pencapaian',
                  '${achievement.toStringAsFixed(0)}%',
                  Icons.trending_up,
                ),
              ],
            ),
            if (snapshot.hasError)
              Text('Gagal memuat produksi: ${snapshot.error}'),
            if (rows.isEmpty &&
                snapshot.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator()),
            ...rows.map(
              (row) => Card(
                child: ListTile(
                  title: Text('${row['style_name']} • ${row['process']}'),
                  subtitle: Text(
                    '${row['line_name']} • ${row['actual']} / '
                    '${row['target']} pcs • defect ${row['defects'] ?? 0}',
                  ),
                  trailing: Text(
                    '${row['created_at']}'.split('T').first,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 42) / 2,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 8),
              Text(label),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DataList extends StatelessWidget {
  const _DataList({
    required this.db,
    required this.table,
    required this.isOperator,
    required this.isLeader,
    required this.onEdit,
    required this.onDelete,
  });

  final SupabaseClient db;
  final String table;
  final bool isOperator;
  final bool isLeader;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: db
          .from(table)
          .stream(primaryKey: ['id'])
          .order(
            isOperator ? 'name' : 'created_at',
            ascending: isOperator,
          ),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              isOperator ? 'Operator dan skill' : 'Produksi, proses dan target',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (snapshot.hasError)
              Text('Gagal memuat data: ${snapshot.error}'),
            if (rows.isEmpty && !snapshot.hasError)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Belum ada data.'),
              ),
            ...rows.map(
              (row) => Card(
                child: ListTile(
                  title: Text(
                    isOperator
                        ? '${row['name']}'
                        : '${row['style_name']} • ${row['process']}',
                  ),
                  subtitle: Text(
                    isOperator
                        ? '${row['line_name']} • ${row['main_process']}\n'
                            'Skill: ${jsonEncode(row['skills'] ?? [])}'
                        : '${row['line_name']} • aktual ${row['actual']} / '
                            '${row['target']} • defect ${row['defects'] ?? 0} • '
                            'downtime ${row['downtime_minutes'] ?? 0} menit',
                  ),
                  isThreeLine: true,
                  trailing: isLeader
                      ? PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'edit') {
                              onEdit(row);
                            } else {
                              onDelete(row);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Hapus'),
                            ),
                          ],
                        )
                      : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
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

  static const _operatorFields = [
    'name',
    'line_name',
    'main_process',
    'skills',
  ];

  static const _productionFields = [
    'style_name',
    'process',
    'line_name',
    'target',
    'actual',
    'defects',
    'downtime_minutes',
  ];

  List<String> get _names =>
      widget.isOperator ? _operatorFields : _productionFields;

  @override
  void initState() {
    super.initState();
    _fields = {
      for (final name in _names)
        name: TextEditingController(text: _initialValue(name)),
    };
  }

  String _initialValue(String name) {
    final value = widget.row?[name];

    if (name == 'skills' && value is List) {
      return value
          .map((item) => '${item['process']}: ${item['level']}')
          .join('\n');
    }

    if (value != null) return '$value';

    return const {
      'actual': '0',
      'defects': '0',
      'downtime_minutes': '0',
    }[name] ?? '';
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.isOperator
            ? (widget.row == null ? 'Tambah operator' : 'Edit operator')
            : (widget.row == null ? 'Catat produksi' : 'Edit produksi'),
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final name in _names)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextFormField(
                      controller: _fields[name],
                      keyboardType: _isNumeric(name)
                          ? TextInputType.number
                          : TextInputType.text,
                      minLines: name == 'skills' ? 3 : 1,
                      maxLines: name == 'skills' ? 5 : 1,
                      decoration: InputDecoration(
                        labelText: _label(name),
                        hintText: name == 'skills' ? 'Obras: 3' : null,
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (!_isOptional(name) && text.isEmpty) {
                          return 'Wajib diisi.';
                        }
                        if (_isNumeric(name)) {
                          final number = int.tryParse(text);
                          if (number == null ||
                              number < (name == 'target' ? 1 : 0)) {
                            return 'Masukkan angka yang valid.';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;

            final data = <String, dynamic>{};
            for (final name in _names) {
              final value = _fields[name]!.text.trim();

              if (name == 'skills') {
                data[name] = value
                    .split('\n')
                    .where((line) => line.trim().isNotEmpty)
                    .map((line) {
                  final parts = line.split(':');
                  final level = int.tryParse(
                        parts.length > 1 ? parts.last.trim() : '1',
                      ) ??
                      1;
                  return {
                    'process': parts.first.trim(),
                    'level': level.clamp(1, 5),
                  };
                }).toList();
              } else if (_isNumeric(name)) {
                data[name] = int.parse(value.isEmpty ? '0' : value);
              } else {
                data[name] = value;
              }
            }

            Navigator.pop(context, data);
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }

  bool _isNumeric(String name) =>
      const {'target', 'actual', 'defects', 'downtime_minutes'}.contains(name);

  bool _isOptional(String name) =>
      const {'skills', 'actual', 'defects', 'downtime_minutes'}.contains(name);

  String _label(String name) => const {
        'name': 'Nama operator',
        'line_name': 'Line',
        'main_process': 'Proses utama',
        'skills': 'Skill per baris (proses: level)',
        'style_name': 'Style',
        'process': 'Proses',
        'target': 'Target pcs',
        'actual': 'Aktual pcs',
        'defects': 'Defect pcs',
        'downtime_minutes': 'Downtime menit',
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
    if (_apiBaseUrl.isEmpty) {
      setState(() => _answer = 'API_BASE_URL belum diatur pada build.');
      return;
    }

    setState(() {
      _busy = true;
      _answer = '';
    });

    try {
      final token = widget.db.auth.currentSession?.accessToken;
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/v1/ai/analyze'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'question':
                  'Analisis bottleneck produksi sewing dan berikan tindakan prioritas.',
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Backend ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      setState(() {
        _answer = data['analysis']?.toString() ?? 'Tidak ada hasil analisis.';
      });
    } catch (error) {
      setState(() => _answer = 'Analisis gagal: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'AI problem solving',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Rekomendasi AI adalah bantuan analisis, bukan bukti sebab-akibat. '
          'Validasi kondisi di lantai produksi.',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _analyze,
          icon: const Icon(Icons.auto_awesome),
          label: Text(_busy ? 'Menganalisis...' : 'Analisis produksi'),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_answer),
          ),
        ),
      ],
    );
  }
}
