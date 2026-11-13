import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const LeaderToolkitApp());

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
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: const ToolkitHome(),
      );
}

class Skill {
  const Skill(this.process, this.level);
  final String process;
  final int level;

  Map<String, dynamic> toJson() => {'process': process, 'level': level};
  factory Skill.fromJson(Map<String, dynamic> json) =>
      Skill(json['process'] as String? ?? '', (json['level'] as num?)?.toInt() ?? 1);
}

class SewingOperator {
  const SewingOperator({
    required this.id,
    required this.name,
    required this.line,
    required this.process,
    required this.skills,
  });

  final String id;
  final String name;
  final String line;
  final String process;
  final List<Skill> skills;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'line': line,
        'process': process,
        'skills': skills.map((skill) => skill.toJson()).toList(),
      };

  factory SewingOperator.fromJson(Map<String, dynamic> json) => SewingOperator(
        id: json['id'] as String? ?? UniqueKey().toString(),
        name: json['name'] as String? ?? '',
        line: json['line'] as String? ?? '',
        process: json['process'] as String? ?? '',
        skills: (json['skills'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(Skill.fromJson)
            .toList(),
      );
}

class StyleProduction {
  const StyleProduction({
    required this.id,
    required this.name,
    required this.process,
    required this.target,
    required this.actual,
  });

  final String id;
  final String name;
  final String process;
  final int target;
  final int actual;

  double get achievement => target <= 0 ? 0 : actual / target * 100;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'process': process,
        'target': target,
        'actual': actual,
      };

  factory StyleProduction.fromJson(Map<String, dynamic> json) => StyleProduction(
        id: json['id'] as String? ?? UniqueKey().toString(),
        name: json['name'] as String? ?? '',
        process: json['process'] as String? ?? '',
        target: (json['target'] as num?)?.toInt() ?? 0,
        actual: (json['actual'] as num?)?.toInt() ?? 0,
      );
}

class ToolkitHome extends StatefulWidget {
  const ToolkitHome({super.key});

  @override
  State<ToolkitHome> createState() => _ToolkitHomeState();
}

class _ToolkitHomeState extends State<ToolkitHome> {
  static const _operatorsKey = 'operators_v1';
  static const _stylesKey = 'styles_v1';

  List<SewingOperator> _operators = [];
  List<StyleProduction> _styles = [];
  int _tab = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final operatorJson = jsonDecode(prefs.getString(_operatorsKey) ?? '[]') as List<dynamic>;
      final styleJson = jsonDecode(prefs.getString(_stylesKey) ?? '[]') as List<dynamic>;
      _operators = operatorJson
          .whereType<Map<String, dynamic>>()
          .map(SewingOperator.fromJson)
          .toList();
      _styles = styleJson
          .whereType<Map<String, dynamic>>()
          .map(StyleProduction.fromJson)
          .toList();
    } catch (_) {
      _operators = [];
      _styles = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_operatorsKey, jsonEncode(_operators.map((e) => e.toJson()).toList()));
    await prefs.setString(_stylesKey, jsonEncode(_styles.map((e) => e.toJson()).toList()));
  }

  Future<void> _editOperator([SewingOperator? existing]) async {
    final result = await showDialog<SewingOperator>(
      context: context,
      builder: (_) => OperatorFormDialog(operator: existing),
    );
    if (result == null) return;
    setState(() {
      final index = _operators.indexWhere((item) => item.id == result.id);
      if (index < 0) {
        _operators = [..._operators, result];
      } else {
        _operators = [..._operators]..[index] = result;
      }
    });
    await _saveData();
  }

  Future<void> _editStyle([StyleProduction? existing]) async {
    final result = await showDialog<StyleProduction>(
      context: context,
      builder: (_) => StyleFormDialog(style: existing),
    );
    if (result == null) return;
    setState(() {
      final index = _styles.indexWhere((item) => item.id == result.id);
      if (index < 0) {
        _styles = [..._styles, result];
      } else {
        _styles = [..._styles]..[index] = result;
      }
    });
    await _saveData();
  }

  Future<void> _deleteOperator(SewingOperator operator) async {
    if (!await _confirmDelete(operator.name)) return;
    setState(() => _operators = _operators.where((item) => item.id != operator.id).toList());
    await _saveData();
  }

  Future<void> _deleteStyle(StyleProduction style) async {
    if (!await _confirmDelete(style.name)) return;
    setState(() => _styles = _styles.where((item) => item.id != style.id).toList());
    await _saveData();
  }

  Future<bool> _confirmDelete(String name) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hapus data?'),
          content: Text('Data "$name" akan dihapus dari perangkat.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
            FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final pages = <Widget>[
      DashboardPage(operators: _operators, styles: _styles),
      OperatorsPage(operators: _operators, onEdit: _editOperator, onDelete: _deleteOperator),
      StylesPage(styles: _styles, onEdit: _editStyle, onDelete: _deleteStyle),
      InsightsPage(operators: _operators, styles: _styles),
    ];
    final canAdd = _tab == 1 || _tab == 2;
    return Scaffold(
      appBar: AppBar(title: const Text('Leader Toolkit'), centerTitle: false),
      body: IndexedStack(index: _tab, children: pages),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () => _tab == 1 ? _editOperator() : _editStyle(),
              icon: const Icon(Icons.add),
              label: Text(_tab == 1 ? 'Tambah operator' : 'Tambah style'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Ringkasan'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Operator'),
          NavigationDestination(icon: Icon(Icons.checkroom_outlined), selectedIcon: Icon(Icons.checkroom), label: 'Style'),
          NavigationDestination(icon: Icon(Icons.lightbulb_outline), selectedIcon: Icon(Icons.lightbulb), label: 'Insight'),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.operators, required this.styles});
  final List<SewingOperator> operators;
  final List<StyleProduction> styles;

  @override
  Widget build(BuildContext context) {
    final totalTarget = styles.fold<int>(0, (sum, style) => sum + style.target);
    final totalActual = styles.fold<int>(0, (sum, style) => sum + style.actual);
    final attainment = totalTarget == 0 ? 0.0 : totalActual / totalTarget * 100;
    final belowTarget = styles.where((style) => style.actual < style.target).length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Ringkasan produksi', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Data tersimpan di perangkat ini dan tetap tersedia saat offline.'),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _MetricCard(label: 'Operator', value: '${operators.length}', icon: Icons.people, color: Colors.blue),
          _MetricCard(label: 'Style aktif', value: '${styles.length}', icon: Icons.checkroom, color: Colors.purple),
          _MetricCard(label: 'Output / target', value: '$totalActual / $totalTarget', icon: Icons.track_changes, color: Colors.teal),
          _MetricCard(label: 'Pencapaian', value: '${attainment.toStringAsFixed(0)}%', icon: Icons.trending_up, color: Colors.orange),
        ]),
        const SizedBox(height: 24),
        Text('Pantauan style', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (styles.isEmpty)
          const _EmptyState(message: 'Belum ada data style. Buka tab Style untuk menambahkan target dan output.')
        else
          ...styles.map((style) => _StyleCard(style: style, compact: true)),
        if (styles.isNotEmpty && belowTarget > 0) ...[
          const SizedBox(height: 8),
          Text('$belowTarget style masih di bawah target.', style: TextStyle(color: Colors.orange[900], fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}

class OperatorsPage extends StatelessWidget {
  const OperatorsPage({super.key, required this.operators, required this.onEdit, required this.onDelete});
  final List<SewingOperator> operators;
  final ValueChanged<SewingOperator> onEdit;
  final ValueChanged<SewingOperator> onDelete;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          Text('Operator sewing', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (operators.isEmpty)
            const _EmptyState(message: 'Belum ada operator. Tekan “Tambah operator” untuk mulai mengisi data.')
          else
            ...operators.map((operator) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(operator.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                        IconButton(tooltip: 'Edit', onPressed: () => onEdit(operator), icon: const Icon(Icons.edit_outlined)),
                        IconButton(tooltip: 'Hapus', onPressed: () => onDelete(operator), icon: const Icon(Icons.delete_outline)),
                      ]),
                      Text('${operator.line} • Proses utama: ${operator.process}'),
                      const SizedBox(height: 8),
                      if (operator.skills.isEmpty)
                        const Text('Belum ada skill dicatat.')
                      else
                        Wrap(spacing: 6, runSpacing: 4, children: operator.skills.map((skill) => Chip(
                              label: Text('${skill.process} • Level ${skill.level}/5'),
                              visualDensity: VisualDensity.compact,
                            )).toList()),
                    ]),
                  ),
                )),
        ],
      );
}

class StylesPage extends StatelessWidget {
  const StylesPage({super.key, required this.styles, required this.onEdit, required this.onDelete});
  final List<StyleProduction> styles;
  final ValueChanged<StyleProduction> onEdit;
  final ValueChanged<StyleProduction> onDelete;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          Text('Style, proses & target', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (styles.isEmpty)
            const _EmptyState(message: 'Belum ada style. Tambahkan style, proses, target harian, dan output aktual.')
          else
            ...styles.map((style) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Column(children: [
                    ListTile(
                      title: Text(style.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${style.process} • Target ${style.target} • Aktual ${style.actual}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) => value == 'edit' ? onEdit(style) : onDelete(style),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit target/output')),
                          PopupMenuItem(value: 'delete', child: Text('Hapus style')),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        LinearProgressIndicator(value: (style.achievement / 100).clamp(0.0, 1.0), minHeight: 8),
                        const SizedBox(height: 6),
                        Text('Pencapaian ${style.achievement.toStringAsFixed(1)}% • Selisih ${style.actual - style.target} pcs'),
                      ]),
                    ),
                  ]),
                )),
        ],
      );
}

class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key, required this.operators, required this.styles});
  final List<SewingOperator> operators;
  final List<StyleProduction> styles;

  @override
  Widget build(BuildContext context) {
    final issues = <({String title, String detail, IconData icon})>[];
    for (final style in styles.where((item) => item.target > 0 && item.actual < item.target * .9)) {
      issues.add((title: 'Periksa proses ${style.process}', detail: '${style.name}: ${style.actual} dari target ${style.target} (${style.achievement.toStringAsFixed(0)}%). Validasi downtime, material, kualitas, dan keseimbangan beban sebelum menentukan tindakan.', icon: Icons.warning_amber));
    }
    for (final operator in operators.where((item) => item.skills.isEmpty || item.skills.every((skill) => skill.level <= 2))) {
      issues.add((title: 'Rencana coaching operator', detail: '${operator.name} di ${operator.line} belum memiliki skill level tinggi yang tercatat. Verifikasi observasi kerja dan buat coaching pada proses ${operator.process}.', icon: Icons.school_outlined));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Insight produksi', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Insight lokal berbasis aturan; ini bukan diagnosis sebab-akibat AI. Catat downtime/defect untuk analisis yang lebih akurat.'),
      const SizedBox(height: 12),
      if (issues.isEmpty)
        const _EmptyState(message: 'Belum ditemukan kondisi yang memicu peringatan, atau belum cukup data. Periksa kembali pencatatan target dan aktual.')
      else
        ...issues.map((issue) => Card(
              child: ListTile(
                leading: Icon(issue.icon, color: Colors.orange[800]),
                title: Text(issue.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(issue.detail)),
                isThreeLine: true,
              ),
            )),
    ]);
  }
}

class OperatorFormDialog extends StatefulWidget {
  const OperatorFormDialog({super.key, this.operator});
  final SewingOperator? operator;

  @override
  State<OperatorFormDialog> createState() => _OperatorFormDialogState();
}

class _OperatorFormDialogState extends State<OperatorFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _line;
  late final TextEditingController _process;
  late final TextEditingController _skills;

  @override
  void initState() {
    super.initState();
    final operator = widget.operator;
    _name = TextEditingController(text: operator?.name ?? '');
    _line = TextEditingController(text: operator?.line ?? '');
    _process = TextEditingController(text: operator?.process ?? '');
    _skills = TextEditingController(text: operator?.skills.map((skill) => '${skill.process}: ${skill.level}').join('\n') ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _line.dispose();
    _process.dispose();
    _skills.dispose();
    super.dispose();
  }

  List<Skill> _parseSkills() {
    return _skills.text.split('\n').map((line) {
      final parts = line.split(':');
      final process = parts.first.trim();
      final level = parts.length > 1 ? int.tryParse(parts.last.trim()) ?? 1 : 1;
      return Skill(process, level.clamp(1, 5));
    }).where((skill) => skill.process.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.operator == null ? 'Tambah operator' : 'Edit operator'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nama operator'), validator: _required),
              const SizedBox(height: 12),
              TextFormField(controller: _line, decoration: const InputDecoration(labelText: 'Line / tim'), validator: _required),
              const SizedBox(height: 12),
              TextFormField(controller: _process, decoration: const InputDecoration(labelText: 'Proses utama (contoh: Obras)'), validator: _required),
              const SizedBox(height: 12),
              TextFormField(
                controller: _skills,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Skill per proses', hintText: 'Sambung: 4\nObras: 2', helperText: 'Satu skill per baris, level 1–5.'),
                validator: (value) {
                  for (final line in (value ?? '').split('\n').where((line) => line.trim().isNotEmpty)) {
                    final parts = line.split(':');
                    if (parts.length > 1) {
                      final level = int.tryParse(parts.last.trim());
                      if (level == null || level < 1 || level > 5) return 'Level skill harus angka 1–5.';
                    }
                  }
                  return null;
                },
              ),
            ])),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, SewingOperator(
              id: widget.operator?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
              name: _name.text.trim(),
              line: _line.text.trim(),
              process: _process.text.trim(),
              skills: _parseSkills(),
            ));
          }, child: const Text('Simpan')),
        ],
      );
}

class StyleFormDialog extends StatefulWidget {
  const StyleFormDialog({super.key, this.style});
  final StyleProduction? style;

  @override
  State<StyleFormDialog> createState() => _StyleFormDialogState();
}

class _StyleFormDialogState extends State<StyleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _process;
  late final TextEditingController _target;
  late final TextEditingController _actual;

  @override
  void initState() {
    super.initState();
    final style = widget.style;
    _name = TextEditingController(text: style?.name ?? '');
    _process = TextEditingController(text: style?.process ?? '');
    _target = TextEditingController(text: style?.target.toString() ?? '');
    _actual = TextEditingController(text: style?.actual.toString() ?? '0');
  }

  @override
  void dispose() {
    _name.dispose();
    _process.dispose();
    _target.dispose();
    _actual.dispose();
    super.dispose();
  }

  String? _positiveInteger(String? value) {
    final number = int.tryParse(value ?? '');
    if (number == null || number < 0) return 'Masukkan angka 0 atau lebih.';
    return null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.style == null ? 'Tambah style / target' : 'Edit style / output'),
        content: SizedBox(
          width: 440,
          child: Form(key: _formKey, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nama / kode style'), validator: _required),
            const SizedBox(height: 12),
            TextFormField(controller: _process, decoration: const InputDecoration(labelText: 'Proses'), validator: _required),
            const SizedBox(height: 12),
            TextFormField(controller: _target, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Target harian (pcs)'), validator: (value) {
              final error = _positiveInteger(value);
              if (error != null) return error;
              if (int.parse(value!) == 0) return 'Target harus lebih dari 0.';
              return null;
            }),
            const SizedBox(height: 12),
            TextFormField(controller: _actual, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Output aktual (pcs)'), validator: _positiveInteger),
          ]))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, StyleProduction(
              id: widget.style?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
              name: _name.text.trim(),
              process: _process.text.trim(),
              target: int.parse(_target.text),
              actual: int.parse(_actual.text),
            ));
          }, child: const Text('Simpan')),
        ],
      );
}

String? _required(String? value) => (value == null || value.trim().isEmpty) ? 'Bagian ini wajib diisi.' : null;

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: (MediaQuery.sizeOf(context).width - 44) / 2,
        child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(height: 12),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 3),
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ]))),
      );
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({required this.style, this.compact = false});
  final StyleProduction style;
  final bool compact;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${style.name} • ${style.process}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: (style.achievement / 100).clamp(0.0, 1.0), minHeight: 7),
          const SizedBox(height: 6),
          Text('Aktual ${style.actual} / target ${style.target} pcs • ${style.achievement.toStringAsFixed(0)}%'),
        ])),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(padding: const EdgeInsets.all(20), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ])),
      );
}
