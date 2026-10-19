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

class IncomeTablePage extends StatefulWidget {
  const IncomeTablePage({super.key});

  @override
  State<IncomeTablePage> createState() => _IncomeTablePageState();
}

class _IncomeTablePageState extends State<IncomeTablePage>
    with SingleTickerProviderStateMixin {
  final GitHubStore _store = GitHubStore();
  List<IncomeRecord> _records = [];
  bool _loading = true;
  String? _error;
  static const int _pageSize = 10;
  int _shown = _pageSize;

  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    _tab.addListener(() => setState(() {}));
    _init();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
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

  /// 绑定手机号（首次进入必须绑定）。
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

  /// 收益金额颜色：正数红色，负数绿色（用户要求）。
  Color _incomeColor(double v) =>
      v >= 0 ? Colors.red.shade700 : Colors.green.shade700;

  @override
  Widget build(BuildContext context) {
    final showFab = _tab.index == 0;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_store.phone == null || _store.phone!.isEmpty
              ? '记事本'
              : '记事本 · ${_store.phone}'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: '刷新'),
          ],
          bottom: TabBar(
            controller: _tab,
            tabs: const [Tab(text: '表格'), Tab(text: '统计')],
          ),
        ),
        body: _buildBody(),
        floatingActionButton: showFab
            ? FloatingActionButton(
                onPressed: _addRow,
                tooltip: '添加一行',
                child: const Icon(Icons.add),
              )
            : null,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const TabBarView(children: [
        Center(child: CircularProgressIndicator()),
        Center(child: CircularProgressIndicator()),
      ]);
    }
    if (!_store.phoneBound) {
      return const TabBarView(children: [Center(child: Text('请先绑定手机号')), SizedBox()]);
    }
    if (!AppConfig.tokenConfigured) {
      return const TabBarView(children: [
        Center(child: Text('服务端 Token 未配置，暂无法读取数据')),
        SizedBox(),
      ]);
    }
    if (_error != null) {
      return TabBarView(children: [
        Center(child: Text('加载失败：$_error', textAlign: TextAlign.center)),
        Center(child: Text('加载失败：$_error', textAlign: TextAlign.center)),
      ]);
    }
    return TabBarView(children: [
      _buildTableTab(),
      _buildStatsTab(),
    ]);
  }

  // ==================== Tab 1：表格 ====================

  Widget _buildTableTab() {
    final sorted = List<IncomeRecord>.from(_records)
      ..sort((a, b) => a.date.compareTo(b.date));
    // 逐行累计总收益
    double running = 0;
    final cumulative = <double>[];
    for (final r in sorted) {
      running += r.dailyIncome;
      cumulative.add(running);
    }
    final shownCount = _shown.clamp(0, sorted.length);
    final shown = sorted.length <= _shown
        ? sorted
        : sorted.sublist(sorted.length - shownCount);
    final offset = sorted.length - shown.length;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _buildTable(shown, cumulative, offset),
          if (sorted.length > _shown)
            TextButton(
              onPressed: () => setState(() => _shown += _pageSize),
              child: Text('显示更多（共 ${sorted.length} 条，当前显示最近 $shownCount 条）'),
            ),
        ],
      ),
    );
  }

  /// xlsx 风格表格：全边框网格，点击单元格进入编辑页。
  Widget _buildTable(List<IncomeRecord> shown, List<double> cumulative, int offset) {
    const headerStyle = TextStyle(fontWeight: FontWeight.bold);
    final borderColor = Theme.of(context).colorScheme.outlineVariant;

    TableRow headerRow() => TableRow(
          decoration:
              BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
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
                style: TextStyle(color: _incomeColor(r.dailyIncome)),
              ),
            ),
            _cell(
              onTap: () => _openEditor(r),
              alignment: Alignment.centerRight,
              child: Text(total.toStringAsFixed(2),
                  style:
                      TextStyle(fontWeight: FontWeight.bold, color: _incomeColor(total))),
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
        for (var i = 0; i < shown.length; i++) dataRow(shown[i], cumulative[offset + i]),
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

  // ==================== Tab 2：统计 ====================

  Widget _buildStatsTab() {
    return _StatsView(records: _records, incomeColor: _incomeColor);
  }
}

/// 统计页：按月 / 按年切换，显示各周期总收益。
class _StatsView extends StatefulWidget {
  final List<IncomeRecord> records;
  final Color Function(double) incomeColor;

  const _StatsView({required this.records, required this.incomeColor});

  @override
  State<_StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<_StatsView> {
  bool _byMonth = true; // true=按月, false=按年

  /// 按周期分组（倒序），返回 (周期名, 总收益, 记录数)。
  List<(String, double, int)> get _groups {
    final map = <String, double>{};
    final count = <String, int>{};
    for (final r in widget.records) {
      final key = _byMonth
          ? '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}'
          : '${r.date.year}';
      map[key] = (map[key] ?? 0) + r.dailyIncome;
      count[key] = (count[key] ?? 0) + 1;
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final k in keys) (k, map[k]!, count[k]!)];
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('按月')),
            ButtonSegment(value: false, label: Text('按年')),
          ],
          selected: {_byMonth},
          onSelectionChanged: (s) => setState(() => _byMonth = s.first),
        ),
        const SizedBox(height: 12),
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('暂无数据')),
          )
        else ...[
          // 表头
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Expanded(
                  flex: 3,
                  child: Text(_byMonth ? '月份' : '年份',
                      style: const TextStyle(fontWeight: FontWeight.bold))),
              const Expanded(
                  flex: 2,
                  child: Text('笔数',
                      style: TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center)),
              const Expanded(
                  flex: 3,
                  child: Text('总收益',
                      style: TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right)),
            ]),
          ),
          ...groups.map((g) {
            final (period, total, n) = g;
            return Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(children: [
                Expanded(flex: 3, child: Text(period)),
                Expanded(flex: 2, child: Text('$n', textAlign: TextAlign.center)),
                Expanded(
                  flex: 3,
                  child: Text(
                    total.toStringAsFixed(2),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: widget.incomeColor(total),
                    ),
                  ),
                ),
              ]),
            );
          }),
          const SizedBox(height: 12),
          // 全部合计
          Row(
            children: [
              const Spacer(),
              const Text('全部合计：',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text(
                widget.records.fold<double>(0, (s, r) => s + r.dailyIncome)
                    .toStringAsFixed(2),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: widget.incomeColor(
                      widget.records.fold<double>(0, (s, r) => s + r.dailyIncome)),
                ),
              ),
            ],
          ),
        ],
      ],
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
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('当日收益必须是数字')));
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
