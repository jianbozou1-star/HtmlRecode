import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// 一条收益记录。
class IncomeRecord {
  final String id;
  final String name; // 名称
  final DateTime date; // 时间
  final double dailyIncome; // 当日收益
  final double nextDayIncome; // 第二日收益

  IncomeRecord({
    required this.id,
    required this.name,
    required this.date,
    required this.dailyIncome,
    this.nextDayIncome = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'date': date.toIso8601String(),
        'dailyIncome': dailyIncome,
        'nextDayIncome': nextDayIncome,
      };

  static IncomeRecord fromJson(Map<String, dynamic> j) => IncomeRecord(
        id: j['id'] as String,
        name: j['name'] ?? '',
        date: DateTime.tryParse(j['date'] ?? '') ?? DateTime.now(),
        dailyIncome: (j['dailyIncome'] as num?)?.toDouble() ?? 0,
        nextDayIncome: (j['nextDayIncome'] as num?)?.toDouble() ?? 0,
      );
}

/// GitHub 存储：数据按绑定的手机号隔离，存于 data/<手机号>/table.json。
class GitHubStore {
  static const _phoneKey = 'bound_phone';
  static const _tableCacheKey = 'table_cache';

  String? _phone;
  String? get phone => _phone;

  /// 是否已绑定手机号且 Token 已配置。
  bool get isReady => (_phone?.isNotEmpty ?? false) && AppConfig.tokenConfigured;

  bool get phoneBound => _phone?.isNotEmpty ?? false;

  String get _filePath => 'data/$_phone/table.json';

  List<IncomeRecord> _tableCache = [];
  List<IncomeRecord> get localTable => List.unmodifiable(_tableCache);

  Future<void> loadLocal() async {
    final sp = await SharedPreferences.getInstance();
    _phone = sp.getString(_phoneKey);
    final tcache = sp.getString(_tableCacheKey);
    if (tcache != null) {
      final list = jsonDecode(tcache) as List;
      _tableCache = list.map((e) => IncomeRecord.fromJson(e as Map<String, dynamic>)).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
    }
  }

  /// 绑定手机号（仅存浏览器本地，用于隔离数据目录）。
  Future<void> bindPhone(String phone) async {
    _phone = phone.trim();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_phoneKey, _phone!);
    // 换号后清空本地缓存，避免显示他人数据
    _tableCache = [];
    await sp.remove(_tableCacheKey);
  }

  Future<void> _cacheTable(List<IncomeRecord> records) async {
    _tableCache = records..sort((a, b) => a.date.compareTo(b.date));
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_tableCacheKey, jsonEncode(_tableCache.map((r) => r.toJson()).toList()));
  }

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer ${AppConfig.token}',
      };

  Uri _api(String p) => Uri.parse('https://api.github.com$p');

  /// 从 GitHub 拉取当前手机号的 table.json。
  Future<List<IncomeRecord>> fetchTable() async {
    final uri = _api(
        '/repos/${AppConfig.owner}/${AppConfig.repo}/contents/$_filePath?ref=${AppConfig.branch}');
    final resp = await http.get(uri, headers: _headers);
    if (resp.statusCode == 404) {
      await _cacheTable([]);
      return [];
    }
    if (resp.statusCode != 200) {
      throw Exception('GitHub 读取失败 (${resp.statusCode}): ${resp.body}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final content = body['content'] as String? ?? '';
    final decoded = utf8.decode(base64Decode(content.replaceAll('\n', '')));
    final list = jsonDecode(decoded) as List;
    final records = list.map((e) => IncomeRecord.fromJson(e as Map<String, dynamic>)).toList();
    await _cacheTable(records);
    return records;
  }

  /// 全量保存当前手机号的收益表。
  Future<void> saveTable(List<IncomeRecord> records) async {
    final uri = _api('/repos/${AppConfig.owner}/${AppConfig.repo}/contents/$_filePath');
    // 取当前 sha（存在则更新）
    String? sha;
    final head = await http.get(uri, headers: _headers);
    if (head.statusCode == 200) {
      sha = (jsonDecode(head.body) as Map<String, dynamic>)['sha'] as String?;
    }
    final jsonStr = const JsonEncoder.withIndent('  ')
        .convert(records.map((r) => r.toJson()).toList());
    final resp = await http.put(
      uri,
      headers: _headers,
      body: jsonEncode({
        'message': 'update table ${DateTime.now().toIso8601String()}',
        'content': base64Encode(utf8.encode(jsonStr)),
        'branch': AppConfig.branch,
        if (sha != null) 'sha': sha,
      }),
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('GitHub 写入失败 (${resp.statusCode}): ${resp.body}');
    }
    await _cacheTable(records);
  }
}
