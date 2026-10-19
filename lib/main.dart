import 'package:flutter/material.dart';

import 'notes_store.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GitHub 记事本',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const RootPage(),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [NotesHomePage(), IncomeTablePage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.notes), label: '记事'),
          NavigationDestination(icon: Icon(Icons.table_chart), label: '收益表'),
        ],
      ),
    );
  }
}

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key});

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final GitHubStore _store = GitHubStore();
  List<Note> _notes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _store.loadLocal();
    setState(() {
      _notes = _store.localNotes;
      _loading = false;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_store.config == null || !_store.config!.isComplete) {
      _showSnack('尚未配置 GitHub，请在右上角设置中填写');
      return;
    }
    setState(() => _loading = true);
    try {
      final notes = await _store.fetchNotes();
      setState(() {
        _notes = notes;
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

  Future<void> _openEditor([Note? note]) async {
    final result = await Navigator.push<Note>(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)),
    );
    if (result == null) return;
    final notes = List<Note>.from(_notes);
    final idx = notes.indexWhere((n) => n.id == result.id);
    if (idx >= 0) {
      notes[idx] = result;
    } else {
      notes.add(result);
    }
    setState(() => _notes = notes);
    await _push(notes);
  }

  Future<void> _deleteNote(Note note) async {
    final notes = List<Note>.from(_notes)..removeWhere((n) => n.id == note.id);
    setState(() => _notes = notes);
    await _push(notes);
  }

  Future<void> _push(List<Note> notes) async {
    if (_store.config == null || !_store.config!.isComplete) {
      _showSnack('未配置 GitHub，数据仅保存在本地缓存');
      return;
    }
    try {
      await _store.saveNotes(notes);
      _showSnack('已同步到 GitHub');
    } catch (e) {
      _showSnack('同步失败：$e');
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SettingsPage(store: _store)),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _store.config;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GitHub 记事本'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: '刷新'),
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings, tooltip: '设置'),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: cfg == null || !cfg.isComplete ? FloatingActionButtonLocation.endTop : null,
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text('加载失败：$_error', textAlign: TextAlign.center));
    }
    if (_notes.isEmpty) {
      return const Center(child: Text('暂无记事，点右下角 + 新建'));
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        itemCount: _notes.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final n = _notes[i];
          return ListTile(
            title: Text(n.title.isEmpty ? '(无标题)' : n.title,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              n.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              '${n.updatedAt.year}-${n.updatedAt.month.toString().padLeft(2, '0')}-${n.updatedAt.day.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            onTap: () => _openEditor(n),
            onLongPress: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('删除记事'),
                  content: Text('确定删除「${n.title}」吗？将同步删除 GitHub 上的数据。'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                  ],
                ),
              );
              if (ok == true) await _deleteNote(n);
            },
          );
        },
      ),
    );
  }
}

class NoteEditorPage extends StatefulWidget {
  final Note? note;
  const NoteEditorPage({super.key, this.note});

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _content;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note?.title ?? '');
    _content = TextEditingController(text: widget.note?.content ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? '新建记事' : '编辑记事'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              final now = DateTime.now();
              Navigator.pop(
                context,
                Note(
                  id: widget.note?.id ??
                      now.millisecondsSinceEpoch.toRadixString(36),
                  title: _title.text.trim(),
                  content: _content.text,
                  updatedAt: now,
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: '标题', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _content,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  labelText: '内容',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final GitHubStore store;
  const SettingsPage({super.key, required this.store});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _owner;
  late final TextEditingController _repo;
  late final TextEditingController _token;
  late final TextEditingController _path;
  late final TextEditingController _branch;

  @override
  void initState() {
    super.initState();
    final c = widget.store.config;
    _owner = TextEditingController(text: c?.owner ?? '');
    _repo = TextEditingController(text: c?.repo ?? '');
    _token = TextEditingController(text: c?.token ?? '');
    _path = TextEditingController(text: c?.path ?? 'notes.json');
    _branch = TextEditingController(text: c?.branch ?? 'main');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GitHub 设置'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () async {
              await widget.store.saveConfig(GitHubConfig(
                owner: _owner.text.trim(),
                repo: _repo.text.trim(),
                token: _token.text.trim(),
                path: _path.text.trim().isEmpty ? 'notes.json' : _path.text.trim(),
                branch: _branch.text.trim().isEmpty ? 'main' : _branch.text.trim(),
              ));
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _owner, decoration: const InputDecoration(labelText: 'GitHub 用户名 (owner)')),
          TextField(controller: _repo, decoration: const InputDecoration(labelText: '仓库名 (repo)')),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Personal Access Token（需 Contents 读写权限）',
              helperText: '只保存在当前浏览器 localStorage，不会上传',
            ),
          ),
          TextField(controller: _path, decoration: const InputDecoration(labelText: '数据文件路径')),
          TextField(controller: _branch, decoration: const InputDecoration(labelText: '分支')),
          const SizedBox(height: 16),
          const Text(
            'Token 创建方式：GitHub → Settings → Developer settings → '
            'Fine-grained tokens，选择该仓库并授予 Contents: Read and write。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

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
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_store.config == null || !_store.config!.isComplete) return;
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

  /// 按时间排序后的记录，并逐行累计总收益。
  List<MapEntry<IncomeRecord, double>> get _rows {
    final sorted = List<IncomeRecord>.from(_records)
      ..sort((a, b) => a.date.compareTo(b.date));
    double total = 0;
    return sorted.map((r) {
      total += r.dailyIncome;
      return MapEntry(r, total);
    }).toList();
  }

  double get _grandTotal =>
      _records.fold(0, (sum, r) => sum + r.dailyIncome);

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openEditor([IncomeRecord? record]) async {
    final result = await showDialog<IncomeRecord>(
      context: context,
      builder: (_) => _RecordDialog(record: record),
    );
    if (result == null) return;
    final records = List<IncomeRecord>.from(_records);
    final idx = records.indexWhere((r) => r.id == result.id);
    if (idx >= 0) {
      records[idx] = result;
    } else {
      records.add(result);
    }
    setState(() => _records = records);
    await _push(records);
  }

  Future<void> _delete(IncomeRecord record) async {
    final records = List<IncomeRecord>.from(_records)..removeWhere((r) => r.id == record.id);
    setState(() => _records = records);
    await _push(records);
  }

  Future<void> _push(List<IncomeRecord> records) async {
    if (_store.config == null || !_store.config!.isComplete) {
      _showSnack('未配置 GitHub，数据仅保存在本地缓存');
      return;
    }
    try {
      await _store.saveTable(records);
      _showSnack('已同步到 GitHub');
    } catch (e) {
      _showSnack('同步失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('收益表'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: '刷新'),
        ],
      ),
      body: _buildBody(rows),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(List<MapEntry<IncomeRecord, double>> rows) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('加载失败：$_error', textAlign: TextAlign.center));
    if (rows.isEmpty) return const Center(child: Text('暂无记录，点右下角 + 新增'));

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        children: [
          // 表头
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: const Row(children: [
              Expanded(flex: 3, child: Text('名称', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(flex: 3, child: Text('时间', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('当日收益', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
              Expanded(flex: 2, child: Text('总收益', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
            ]),
          ),
          ...rows.map((entry) {
            final r = entry.key;
            final total = entry.value;
            return InkWell(
              onTap: () => _openEditor(r),
              onLongPress: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('删除记录'),
                    content: Text('确定删除「${r.name}」吗？将同步删除 GitHub 上的数据。'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                    ],
                  ),
                );
                if (ok == true) await _delete(r);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Expanded(flex: 3, child: Text(r.name, overflow: TextOverflow.ellipsis)),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}-${r.date.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      r.dailyIncome.toStringAsFixed(2),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: r.dailyIncome >= 0 ? Colors.green.shade700 : Colors.red.shade700),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(total.toStringAsFixed(2),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ]),
              ),
            );
          }),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                const Spacer(),
                const Text('累计总收益：',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(
                  _grandTotal.toStringAsFixed(2),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: _grandTotal >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordDialog extends StatefulWidget {
  final IncomeRecord? record;
  const _RecordDialog({this.record});

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  late final TextEditingController _name;
  late final TextEditingController _income;
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.record?.name ?? '');
    _income = TextEditingController(
        text: widget.record == null ? '' : widget.record!.dailyIncome.toStringAsFixed(2));
    if (widget.record != null) _date = widget.record!.date;
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
    return AlertDialog(
      title: Text(widget.record == null ? '新增记录' : '编辑记录'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: '名称')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text(
                '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
              ),
            ),
            TextButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month),
              label: const Text('选日期'),
            ),
          ]),
          TextField(
            controller: _income,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: '当日收益（可为负数）'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final income = double.tryParse(_income.text.trim());
            if (income == null) return;
            Navigator.pop(
              context,
              IncomeRecord(
                id: widget.record?.id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36),
                name: _name.text.trim(),
                date: _date,
                dailyIncome: income,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
