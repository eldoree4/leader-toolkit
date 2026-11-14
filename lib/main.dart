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
  Widget build(BuildContext context) => MaterialApp(
        title: 'Leader Toolkit',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1769AA)),
          scaffoldBackgroundColor: const Color(0xFFF4F7FB),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        home: const _HomePage(),
      );
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

  List<Map<String, dynamic>> _decode(String? json) {
    if (json == null || json.isEmpty) return [];
    return (jsonDecode(json) as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final operators = _decode(prefs.getString(_operatorsKey));
      final entries = _decode(prefs.getString(_productionKey));
      if (!mounted) return;
      setState(() {
        _operators = operators;
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Gagal membaca data lokal: $error');
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_operatorsKey, jsonEncode(_operators));
    await prefs.setString(_productionKey, jsonEncode(_entries));
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _edit({required bool operatorRecord, int? index}) async {
    final records = operatorRecord ? _operators : _entries;
    final old = index == null ? null : records[index];
    final specs = operatorRecord
        ? const [
            _Field('name', 'Nama operator'),
            _Field('line_name', 'Line'),
            _Field('main_process', 'Proses utama'),
            _Field('skills', 'Skill (contoh: Obras level 3)', optional: true),
          ]
        : const [
            _Field('style_name', 'Style'),
            _Field('process', 'Proses'),
            _Field('line_name', 'Line'),
            _Field('target', 'Target pcs', numeric: true),
            _Field('actual', 'Aktual pcs', numeric: true),
            _Field('defects', 'Defect pcs', numeric: true, optional: true),
            _Field('downtime_minutes', 'Downtime menit', numeric: true, optional: true),
          ];
    final controllers = <String, TextEditingController>{
      for (final field in specs)
        field.key: TextEditingController(
          text: old == null ? (field.numeric ? '0' : '') : '${old[field.key] ?? ''}',
        ),
    };

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(operatorRecord
            ? (old == null ? 'Tambah operator' : 'Edit operator')
            : (old == null ? 'Catat produksi' : 'Edit produksi')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in specs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: controllers[field.key],
                      keyboardType: field.numeric ? TextInputType.number : TextInputType.text,
                      decoration: InputDecoration(labelText: field.label),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              final data = <String, dynamic>{};
              for (final field in specs) {
                final value = controllers[field.key]!.text.trim();
                if (!field.optional && value.isEmpty) {
                  _message('${field.label} wajib diisi.');
                  return;
                }
                if (field.numeric) {
                  final number = int.tryParse(value.isEmpty ? '0' : value);
                  if (number == null || number < 0 || (field.key == 'target' && number == 0)) {
                    _message('${field.label} harus berupa angka valid.');
                    return;
                  }
                  data[field.key] = number;
                } else {
                  data[field.key] = value;
                }
              }
              if (!operatorRecord) {
                data['created_at'] = old?['created_at'] ?? DateTime.now().toIso8601String();
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
      if (operatorRecord) {
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
      _message('Data tersimpan di perangkat ini.');
    } catch (error) {
      _message('Gagal menyimpan data lokal: $error');
    }
  }

  Future<void> _delete({required bool operatorRecord, required int index}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus data?'),
        content: const Text('Data akan dihapus dari perangkat ini.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => (operatorRecord ? _operators : _entries).removeAt(index));
    try {
      await _saveData();
      _message('Data dihapus dari perangkat ini.');
    } catch (error) {
      _message('Gagal menyimpan perubahan: $error');
    }
  }

  Future<void> _clearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus semua data lokal?'),
        content: const Text('Tindakan ini tidak dapat dibatalkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Hapus semua')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _operators = [];
      _entries = [];
    });
    await _saveData();
    _message('Semua data lokal sudah dihapus.');
  }

  @override
  Widget build(BuildContext context) {
    const labels = ['Ringkasan', 'Operator', 'Produksi', 'Analisis lokal'];
    return Scaffold(
      appBar: AppBar(
        title: Text('Leader Toolkit • ${labels[_tab]}'),
        actions: [
          IconButton(
            tooltip: 'Hapus semua data lokal',
            onPressed: _clearData,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(index: _tab, children: [
              _Dashboard(entries: _entries),
              _RecordList(
                title: 'Operator dan skill',
                records: _operators,
                operatorRecord: true,
                onEdit: (i) => _edit(operatorRecord: true, index: i),
                onDelete: (i) => _delete(operatorRecord: true, index: i),
              ),
              _RecordList(
                title: 'Produksi, proses dan target',
                records: _entries,
                operatorRecord: false,
                onEdit: (i) => _edit(operatorRecord: false, index: i),
                onDelete: (i) => _delete(operatorRecord: false, index: i),
              ),
              _LocalAnalysis(entries: _entries),
            ]),
      floatingActionButton: (_tab == 1 || _tab == 2) && !_loading
          ? FloatingActionButton.extended(
              onPressed: () => _edit(operatorRecord: _tab == 1),
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
          NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'Analisis'),
        ],
      ),
    );
  }
}

class _Field {
  const _Field(this.key, this.label, {this.numeric = false, this.optional = false});
  final String key;
  final String label;
  final bool numeric;
  final bool optional;
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.entries});
  final List<Map<String, dynamic>> entries;

  @override
  Widget build(BuildContext context) {
    final target = entries.fold<int>(0, (sum, row) => sum + ((row['target'] as num?)?.toInt() ?? 0));
    final actual = entries.fold<int>(0, (sum, row) => sum + ((row['actual'] as num?)?.toInt() ?? 0));
    final defects = entries.fold<int>(0, (sum, row) => sum + ((row['defects'] as num?)?.toInt() ?? 0));
    final achievement = target == 0 ? 0.0 : actual / target * 100;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Ringkasan produksi', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Berjalan offline. Data hanya disimpan di perangkat ini dan tidak disinkronkan.'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Metric('Catatan', '${entries.length}', Icons.receipt_long),
            _Metric('Target', '$target pcs', Icons.flag),
            _Metric('Aktual', '$actual pcs', Icons.check_circle_outline),
            _Metric('Pencapaian', '${achievement.toStringAsFixed(0)}%', Icons.trending_up),
            _Metric('Defect', '$defects pcs', Icons.warning_amber_outlined),
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

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
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

class _RecordList extends StatelessWidget {
  const _RecordList({
    required this.title,
    required this.records,
    required this.operatorRecord,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final List<Map<String, dynamic>> records;
  final bool operatorRecord;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Tersimpan lokal di perangkat ini.'),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('Belum ada data.'),
            ),
          for (var i = 0; i < records.length; i++)
            Card(
              child: ListTile(
                title: Text(
                  operatorRecord
                      ? '${records[i]['name']}'
                      : '${records[i]['style_name']} • ${records[i]['process']}',
                ),
                subtitle: Text(
                  operatorRecord
                      ? '${records[i]['line_name']} • ${records[i]['main_process']}\nSkill: ${records[i]['skills'] ?? '-'}'
                      : '${records[i]['line_name']} • aktual ${records[i]['actual']} / ${records[i]['target']} pcs • defect ${records[i]['defects'] ?? 0} • downtime ${records[i]['downtime_minutes'] ?? 0} menit',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (action) => action == 'edit' ? onEdit(i) : onDelete(i),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Hapus')),
                  ],
                ),
              ),
            ),
        ],
      );
}

class _LocalAnalysis extends StatelessWidget {
  const _LocalAnalysis({required this.entries});
  final List<Map<String, dynamic>> entries;

  @override
  Widget build(BuildContext context) {
    final target = entries.fold<int>(0, (sum, row) => sum + ((row['target'] as num?)?.toInt() ?? 0));
    final actual = entries.fold<int>(0, (sum, row) => sum + ((row['actual'] as num?)?.toInt() ?? 0));
    final defects = entries.fold<int>(0, (sum, row) => sum + ((row['defects'] as num?)?.toInt() ?? 0));
    final percent = target == 0 ? 0.0 : actual / target * 100;
    final analysis = entries.isEmpty
        ? 'Tambahkan catatan produksi terlebih dahulu. Analisis ini berjalan di perangkat dan bukan AI online.'
        : 'Analisis lokal untuk ${entries.length} catatan: pencapaian agregat ${percent.toStringAsFixed(1)}%, total defect $defects pcs. ${percent < 100 ? 'Pencapaian masih di bawah target; periksa proses dengan aktual terendah dan hambatan di line.' : 'Target agregat tercapai; tetap pantau kualitas dan downtime.'}';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Analisis lokal', style: Theme.of(context).textTheme.headlineSmall),
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
}
