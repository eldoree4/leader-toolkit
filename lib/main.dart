import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LeaderToolkitApp());
}

class LeaderToolkitApp extends StatelessWidget {
  const LeaderToolkitApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      home: const _HomePage(),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  static const _operatorsKey = 'leader_toolkit_operators_v1';
  static const _productionKey = 'leader_toolkit_production_v1';

  int _tab = 0;
  bool _loading = true;
  List<Map<String, dynamic>> _operators = [];
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  List<Map<String, dynamic>> _decodeRows(String? value) {
    if (value == null || value.isEmpty) return [];

    final decoded = jsonDecode(value) as List<dynamic>;
    return decoded
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final operators = _decodeRows(prefs.getString(_operatorsKey));
      final entries = _decodeRows(prefs.getString(_productionKey));

      if (!mounted) return;
      setState(() {
        _operators = operators;
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Gagal membaca data lokal: $error');
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_operatorsKey, jsonEncode(_operators));
    await prefs.setString(_productionKey, jsonEncode(_entries));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _editRecord({
    required bool isOperator,
    int? index,
  }) async {
    final records = isOperator ? _operators : _entries;
    final oldRecord = index == null ? null : records[index];

    final fields = isOperator
        ? const [
            _Field('name', 'Nama operator'),
            _Field('line_name', 'Line'),
            _Field('main_process', 'Proses utama'),
            _Field('skills', 'Skill operator', optional: true),
          ]
        : const [
            _Field('style_name', 'Style'),
            _Field('process', 'Proses'),
            _Field('line_name', 'Line'),
            _Field('target', 'Target pcs', numeric: true),
            _Field('actual', 'Aktual pcs', numeric: true),
            _Field('defects', 'Defect pcs', numeric: true, optional: true),
            _Field(
              'downtime_minutes',
              'Downtime menit',
              numeric: true,
              optional: true,
            ),
          ];

    final formKey = GlobalKey<FormState>();
    final controllers = <String, TextEditingController>{
      for (final field in fields)
        field.key: TextEditingController(
          text: oldRecord == null
              ? (field.numeric ? '0' : '')
              : '${oldRecord[field.key] ?? ''}',
        ),
    };

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isOperator
              ? (oldRecord == null ? 'Tambah operator' : 'Edit operator')
              : (oldRecord == null ? 'Catat produksi' : 'Edit produksi'),
        ),
        content: SizedBox(
          width: 440,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final field in fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextFormField(
                        controller: controllers[field.key],
                        keyboardType: field.numeric
                            ? TextInputType.number
                            : TextInputType.text,
                        decoration: InputDecoration(
                          labelText: field.label,
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (!field.optional && text.isEmpty) {
                            return 'Bagian ini wajib diisi.';
                          }
                          if (field.numeric && text.isNotEmpty) {
                            final number = int.tryParse(text);
                            if (number == null || number < 0) {
                              return 'Masukkan angka 0 atau lebih.';
                            }
                            if (field.key == 'target' && number == 0) {
                              return 'Target harus lebih dari 0.';
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;

              final data = <String, dynamic>{};
              for (final field in fields) {
                final value = controllers[field.key]!.text.trim();
                data[field.key] = field.numeric
                    ? int.tryParse(value.isEmpty ? '0' : value) ?? 0
                    : value;
              }

              if (!isOperator) {
                data['created_at'] = oldRecord?['created_at'] ??
                    DateTime.now().toIso8601String();
              }

              Navigator.pop(dialogContext, data);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    for (final controller in controllers.values) {
      controller.dispose();
    }

    if (result == null || !mounted) return;

    setState(() {
      if (isOperator) {
        if (index == null) {
          _operators.add(result);
        } else {
          _operators[index] = result;
        }
      } else if (index == null) {
        _entries.insert(0, result);
      } else {
        _entries[index] = result;
      }
    });

    try {
      await _saveData();
      _showMessage('Data tersimpan di perangkat ini.');
    } catch (error) {
      _showMessage('Gagal menyimpan data lokal: $error');
    }
  }

  Future<void> _deleteRecord({
    required bool isOperator,
    required int index,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus data?'),
        content: const Text('Data akan dihapus dari perangkat ini.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      (isOperator ? _operators : _entries).removeAt(index);
    });

    try {
      await _saveData();
      _showMessage('Data dihapus.');
    } catch (error) {
      _showMessage('Gagal menyimpan perubahan: $error');
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus semua data?'),
        content: const Text(
          'Semua data operator dan produksi di perangkat ini akan dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus semua'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _operators = [];
      _entries = [];
    });

    try {
      await _saveData();
      _showMessage('Semua data lokal sudah dihapus.');
    } catch (error) {
      _showMessage('Gagal menghapus data: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['Ringkasan', 'Operator', 'Produksi', 'Analisis lokal'];

    final pages = <Widget>[
      _Dashboard(
        entries: _entries,
        operatorCount: _operators.length,
      ),
      _RecordList(
        title: 'Operator dan skill',
        records: _operators,
        isOperator: true,
        onEdit: (index) => _editRecord(isOperator: true, index: index),
        onDelete: (index) => _deleteRecord(isOperator: true, index: index),
      ),
      _RecordList(
        title: 'Catatan produksi',
        records: _entries,
        isOperator: false,
        onEdit: (index) => _editRecord(isOperator: false, index: index),
        onDelete: (index) => _deleteRecord(isOperator: false, index: index),
      ),
      _LocalAnalysis(entries: _entries),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Leader Toolkit • ${titles[_tab]}'),
        actions: [
          IconButton(
            tooltip: 'Hapus semua data lokal',
            onPressed: _clearAllData,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(index: _tab, children: pages),
      floatingActionButton: !_loading && (_tab == 1 || _tab == 2)
          ? FloatingActionButton.extended(
              onPressed: () => _editRecord(isOperator: _tab == 1),
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
            icon: Icon(Icons.insights_outlined),
            label: 'Analisis',
          ),
        ],
      ),
    );
  }
}

class _Field {
  const _Field(
    this.key,
    this.label, {
    this.numeric = false,
    this.optional = false,
  });

  final String key;
  final String label;
  final bool numeric;
  final bool optional;
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.entries,
    required this.operatorCount,
  });

  final List<Map<String, dynamic>> entries;
  final int operatorCount;

  @override
  Widget build(BuildContext context) {
    final target = _total(entries, 'target');
    final actual = _total(entries, 'actual');
    final defects = _total(entries, 'defects');
    final achievement = target == 0 ? 0.0 : actual / target * 100;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Ringkasan produksi',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Mode offline: data tersimpan di perangkat ini dan tidak '
          'disinkronkan ke cloud.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricCard('Operator', '$operatorCount', Icons.people_outline),
            _MetricCard('Catatan', '${entries.length}', Icons.receipt_long),
            _MetricCard('Target', '$target pcs', Icons.flag_outlined),
            _MetricCard('Aktual', '$actual pcs', Icons.check_circle_outline),
            _MetricCard(
              'Pencapaian',
              '${achievement.toStringAsFixed(0)}%',
              Icons.trending_up,
            ),
            _MetricCard(
              'Defect',
              '$defects pcs',
              Icons.warning_amber_outlined,
            ),
          ],
        ),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 18),
            child: Text('Belum ada catatan produksi.'),
          ),
      ],
    );
  }
}

int _total(List<Map<String, dynamic>> rows, String key) {
  return rows.fold<int>(
    0,
    (sum, row) => sum + ((row[key] as num?)?.toInt() ?? 0),
  );
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

class _RecordList extends StatelessWidget {
  const _RecordList({
    required this.title,
    required this.records,
    required this.isOperator,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final List<Map<String, dynamic>> records;
  final bool isOperator;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Data tersimpan lokal di perangkat ini.'),
        if (records.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('Belum ada data. Tekan tombol + untuk menambahkan.'),
          ),
        for (var index = 0; index < records.length; index++)
          Card(
            child: ListTile(
              title: Text(
                isOperator
                    ? '${records[index]['name']}'
                    : '${records[index]['style_name']} • '
                        '${records[index]['process']}',
              ),
              subtitle: Text(
                isOperator
                    ? '${records[index]['line_name']} • '
                        '${records[index]['main_process']}\n'
                        'Skill: ${records[index]['skills'] ?? '-'}'
                    : '${records[index]['line_name']} • '
                        'aktual ${records[index]['actual']} / '
                        '${records[index]['target']} pcs • '
                        'defect ${records[index]['defects'] ?? 0} • '
                        'downtime ${records[index]['downtime_minutes'] ?? 0} menit',
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'edit') {
                    onEdit(index);
                  } else if (action == 'delete') {
                    onDelete(index);
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
              ),
            ),
          ),
      ],
    );
  }
}

class _LocalAnalysis extends StatelessWidget {
  const _LocalAnalysis({required this.entries});

  final List<Map<String, dynamic>> entries;

  @override
  Widget build(BuildContext context) {
    final target = _total(entries, 'target');
    final actual = _total(entries, 'actual');
    final defects = _total(entries, 'defects');
    final achievement = target == 0 ? 0.0 : actual / target * 100;

    final lowestEntry = entries.isEmpty
        ? null
        : entries.reduce((a, b) {
            final aRate = _achievementRate(a);
            final bRate = _achievementRate(b);
            return aRate <= bRate ? a : b;
          });

    final analysis = entries.isEmpty
        ? 'Tambahkan catatan produksi untuk melihat ringkasan. '
            'Analisis ini berjalan di perangkat dan bukan AI online.'
        : 'Berdasarkan ${entries.length} catatan, pencapaian agregat '
            'adalah ${achievement.toStringAsFixed(1)}% dengan total '
            '$defects pcs defect.'
            '${lowestEntry == null ? '' : ' Catatan dengan pencapaian terendah: '
                '${lowestEntry['style_name']} • ${lowestEntry['process']} '
                '(${_achievementRate(lowestEntry).toStringAsFixed(1)}%).'} '
            '${achievement < 100 ? 'Periksa hambatan proses dan kebutuhan '
                'dukungan di line.' : 'Target agregat tercapai; terus pantau '
                'kualitas dan downtime.'}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Analisis lokal',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Tidak menggunakan AI, server, atau koneksi internet.'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(analysis),
          ),
        ),
      ],
    );
  }

  double _achievementRate(Map<String, dynamic> row) {
    final target = (row['target'] as num?)?.toDouble() ?? 0;
    final actual = (row['actual'] as num?)?.toDouble() ?? 0;
    return target == 0 ? 0 : actual / target * 100;
  }
}
