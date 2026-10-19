import 'package:flutter/material.dart';

import 'app_config.dart';
import 'notes_store.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '记事本',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const IncomeTablePage(),
    );
  }
}

enum _Period { month, year, all }

class IncomeTablePage extends StatefulWidget {
  const IncomeTablePage({super.key});

  @override
  State<IncomeTablePage> createState() => _IncomeTablePageState();
}

class _IncomeTablePageState extends State<IncomeTablePage> {
  final GitHubStore _store = GitHubStore();
  List<IncomeRecord> _records = [];
  bool _loading = true;
  String? _error;
  _Period _period = _Period.month;
  static const int _pageSize = 10;
  int _shown = _pageSize;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _store.loadLocal();
    setState(() {
      _records = _store.localTable;
      _loading = false;
    });
    if (!_store.phoneBound) {
      await _bindPhone();
    }
    await _refresh();
  }

  /// 绑定手机号（首次进入必须绑定，不弹框就无法继续）。
  Future<void> _bindPhone() async {
    final controller = TextEditingController();
    await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('绑定手机号'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            decoration: const InputDecoration(
              labelText: '手机号',
              helperText: '数据将按手机号隔离存储与读取',
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                final p = controller.text.trim();
                if (p.length == 11) Navigator.pop(context, p);
              },
              child: const Text('绑定'),
            ),
          ],
        ),
      ),
    );
    await _store.bindPhone(controller.text.trim());
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    if (!_store.isReady) return;
    setState(() => _loading = true);
    try {
      final records = await _store.fetchTable();
      setState(() {
        _records = records;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  /// 当前周期内的记录（按时间升序）。
  List<IncomeRecord> get _periodRecords {
    final now = DateTime.now();
    bool inPeriod(IncomeRecord r) {
      switch (_period) {
        case _Period.month:
          return r.date.year == now.year && r.date.month == now.month;
        case _Period.year:
          return r.date.year == now.year;
        case _Period.all:
          return true;
      }
    }

    final list = _records.where(inPeriod).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  double get _periodTotal =>
      _periodRecords.fold(0, (sum, r) => sum + r.dailyIncome);

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 点击 + 直接在表格下方追加一行（默认当天、收益 0），并立即同步。
  Future<void> _addRow() async {
    final now = DateTime.now();
    final record = IncomeRecord(
      id: now.microsecondsSinceEpoch.toRadixString(36),
      name: '${now.month}月${now.day}日记录',
      date: now,
      dailyIncome: 0,
    );
    final records = List<IncomeRecord>.from(_records)..add(record);
    setState(() => _records = records);
    await _push(records);
  }

  /// 编辑走独立页面（不弹框）。
  Future<void> _openEditor(IncomeRecord record) async {
    final result = await Navigator.push<EditResult>(
      context,
      MaterialPageRoute(builder: (_) => RecordEditPage(record: record)),
    );
    if (result == null) return;
    if (result.deleted) {
      // 在编辑页删除
      final records = List<IncomeRecord>.from(_records)
        ..removeWhere((r) => r.id == result.deletedId);
      setState(() => _records = records);
      await _push(records);
      return;
    }
    final records = List<IncomeRecord>.from(_records);
    final idx = records.indexWhere((r) => r.id == result.record!.id);
    if (idx >= 0) records[idx] = result.record!;
    setState(() => _records = records);
    await _push(records);
  }

  Future<void> _push(List<IncomeRecord> records) async {
    if (!_store.isReady) {
      _showSnack('未绑定手机号或 Token 未配置，数据仅保存在本地缓存');
      return;
    }
    try {
      await _store.saveTable(records);
      _showSnack('已同步到 GitHub');
    } catch (e) {
      _showSnack('同步失败：$e');
    }
  }

  String get _periodLabel {
    switch (_period) {
      case _Period.month:
        return '本月';
      case _Period.year:
        return '本年';
      case _Period.all:
        return '全部';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_store.phone == null || _store.phone!.isEmpty
            ? '记事本'
            : '记事本 · ${_store.phone}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: '刷新'),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addRow,
        tooltip: '添加一行',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_store.phoneBound) return const Center(child: Text('请先绑定手机号'));
    if (!AppConfig.tokenConfigured) {
      return const Center(child: Text('服务端 Token 未配置，暂无法读取数据'));
    }
    if (_error != null) return Center(child: Text('加载失败：$_error', textAlign: TextAlign.center));

    final all = _periodRecords;
    // 最近 10 条（默认），可展开更多
    final shownCount = _shown.clamp(0, all.length);
    final shown = all.length <= _shown
        ? all
        : all.sublist(all.length - shownCount);
    // 逐行累计（从周期开始累计）
    double running = 0;
    final cumulative = <double>[];
    for (final r in all) {
      running += r.dailyIncome;
      cumulative.add(running);
    }
    final offset = all.length - shown.length;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          // 周期切换
          SegmentedButton<_Period>(
            segments: const [
              ButtonSegment(value: _Period.month, label: Text('按月')),
              ButtonSegment(value: _Period.year, label: Text('按年')),
              ButtonSegment(value: _Period.all, label: Text('全部')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() {
              _period = s.first;
              _shown = _pageSize;
            }),
          ),
          const SizedBox(height: 8),
          _buildTable(shown, cumulative, offset, all),
          if (all.length > _shown)
            TextButton(
              onPressed: () => setState(() => _shown += _pageSize),
              child: Text('显示更多（共 ${all.length} 条，当前显示最近 $shownCount 条）'),
            ),
          const SizedBox(height: 8),
          // 周期统计
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Text('$_periodLabel收益统计：',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                Text(
                  _periodTotal.toStringAsFixed(2),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: _periodTotal >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// xlsx 风格表格：全边框网格。
  Widget _buildTable(
      List<IncomeRecord> shown, List<double> cumulative, int offset, List<IncomeRecord> all) {
    const headerStyle = TextStyle(fontWeight: FontWeight.bold);
    final borderColor = Theme.of(context).colorScheme.outlineVariant;

    TableRow headerRow() => TableRow(
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
          children: ['名称', '时间', '当日收益', '总收益']
              .map((h) => Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(h, style: headerStyle),
                  ))
              .toList(),
        );

    TableRow dataRow(IncomeRecord r, double total) => TableRow(
          children: [
            _cell(
              onTap: () => _openEditor(r),
              child: Text(r.name.isEmpty ? '-' : r.name, overflow: TextOverflow.ellipsis),
            ),
            _cell(
              onTap: () => _openEditor(r),
              child: Text(
                  '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}-${r.date.day.toString().padLeft(2, '0')}'),
            ),
            _cell(
              onTap: () => _openEditor(r),
              alignment: Alignment.centerRight,
              child: Text(
                r.dailyIncome.toStringAsFixed(2),
                style: TextStyle(
                    color: r.dailyIncome >= 0 ? Colors.green.shade700 : Colors.red.shade700),
              ),
            ),
            _cell(
              onTap: () => _openEditor(r),
              alignment: Alignment.centerRight,
              child: Text(total.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );

    return Table(
      border: TableBorder.all(color: borderColor),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(3),
        2: FlexColumnWidth(2),
        3: FlexColumnWidth(2),
      },
      children: [
        headerRow(),
        for (var i = 0; i < shown.length; i++)
          dataRow(shown[i], cumulative[offset + i]),
      ],
    );
  }

  Widget _cell({
    required Widget child,
    required VoidCallback onTap,
    Alignment alignment = Alignment.centerLeft,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        alignment: alignment,
        constraints: const BoxConstraints(minHeight: 44),
        child: child,
      ),
    );
  }
}

/// 编辑页（独立页面，非弹框）。
class RecordEditPage extends StatefulWidget {
  final IncomeRecord record;
  const RecordEditPage({super.key, required this.record});

  @override
  State<RecordEditPage> createState() => _RecordEditPageState();
}

class _RecordEditPageState extends State<RecordEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _income;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.record.name);
    _income = TextEditingController(text: widget.record.dailyIncome.toStringAsFixed(2));
    _date = widget.record.date;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑记录'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '保存',
            onPressed: () {
              final income = double.tryParse(_income.text.trim());
              if (income == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('当日收益必须是数字')));
                return;
              }
              Navigator.pop(
                context,
                EditResult(
                  record: IncomeRecord(
                    id: widget.record.id,
                    name: _name.text.trim(),
                    date: _date,
                    dailyIncome: income,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('时间'),
            subtitle: Text(
                '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
            trailing: OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month),
              label: const Text('选日期'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _income,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(
              labelText: '当日收益（可为负数）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, EditResult.deleted(widget.record.id)),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除此记录'),
          ),
        ],
      ),
    );
  }
}

/// 编辑页返回结果：保存的记录或删除标记。
class EditResult {
  final IncomeRecord? record;
  final String? deletedId;
  bool get deleted => deletedId != null;

  const EditResult({this.record, this.deletedId});

  factory EditResult.deleted(String id) => EditResult(deletedId: id);
}
