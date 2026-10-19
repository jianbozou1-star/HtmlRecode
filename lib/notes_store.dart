import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// GitHub 配置（owner/repo/token/path），持久化到浏览器 localStorage。
class GitHubConfig {
  final String owner;
  final String repo;
  final String token;
  final String path; // 仓库内数据文件路径，默认 notes.json
  final String branch;

  const GitHubConfig({
    required this.owner,
    required this.repo,
    required this.token,
    this.path = 'notes.json',
    this.branch = 'main',
  });

  bool get isComplete => owner.isNotEmpty && repo.isNotEmpty && token.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'owner': owner,
        'repo': repo,
        'token': token,
        'path': path,
        'branch': branch,
      };

  static GitHubConfig fromJson(Map<String, dynamic> j) => GitHubConfig(
        owner: j['owner'] ?? '',
        repo: j['repo'] ?? '',
        token: j['token'] ?? '',
        path: (j['path']?.isEmpty ?? true) ? 'notes.json' : j['path'],
        branch: (j['branch']?.isEmpty ?? true) ? 'main' : j['branch'],
      );
}

/// 一条记事。
class Note {
  final String id;
  final String title;
  final String content;
  final DateTime updatedAt;

  Note({required this.id, required this.title, required this.content, required this.updatedAt});

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static Note fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        title: j['title'] ?? '',
        content: j['content'] ?? '',
        updatedAt: DateTime.tryParse(j['updatedAt'] ?? '') ?? DateTime.now(),
      );
}

class GitHubStore {
  static const _configKey = 'gh_config';
  static const _cacheKey = 'notes_cache';

  GitHubConfig? _config;
  GitHubConfig? get config => _config;

  /// 本地缓存的记事（离线可读，无 token 时也能看）。
  List<Note> _localNotes = [];
  List<Note> get localNotes => List.unmodifiable(_localNotes);

  Future<void> loadLocal() async {
    final sp = await SharedPreferences.getInstance();
    final cfg = sp.getString(_configKey);
    if (cfg != null) {
      _config = GitHubConfig.fromJson(jsonDecode(cfg) as Map<String, dynamic>);
    }
    final cache = sp.getString(_cacheKey);
    if (cache != null) {
      final list = jsonDecode(cache) as List;
      _localNotes = list.map((e) => Note.fromJson(e as Map<String, dynamic>)).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
  }

  Future<void> saveConfig(GitHubConfig config) async {
    _config = config;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_configKey, jsonEncode(config.toJson()));
  }

  Future<void> _cacheNotes(List<Note> notes) async {
    _localNotes = notes..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_cacheKey, jsonEncode(_localNotes.map((n) => n.toJson()).toList()));
  }

  Uri _api(String p) => Uri.parse('https://api.github.com$p');

  Map<String, String> _headers({bool withAuth = true}) => {
        'Accept': 'application/vnd.github+json',
        if (withAuth && _config!.token.isNotEmpty) 'Authorization': 'Bearer ${_config!.token}',
      };

  /// 从 GitHub 拉取 notes.json。返回最新记事列表。
  Future<List<Note>> fetchNotes() async {
    final c = _config!;
    final uri = _api('/repos/${c.owner}/${c.repo}/contents/${c.path}?ref=${c.branch}');
    final resp = await http.get(uri, headers: _headers());
    if (resp.statusCode == 404) {
      // 文件不存在，视为空数据
      await _cacheNotes([]);
      return [];
    }
    if (resp.statusCode != 200) {
      throw Exception('GitHub 读取失败 (${resp.statusCode}): ${resp.body}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final content = body['content'] as String? ?? '';
    final decoded = utf8.decode(base64Decode(content.replaceAll('\n', '')));
    final list = jsonDecode(decoded) as List;
    final notes = list.map((e) => Note.fromJson(e as Map<String, dynamic>)).toList();
    await _cacheNotes(notes);
    return notes;
  }

  /// 全量保存记事列表（写入 notes.json，一次提交）。
  Future<void> saveNotes(List<Note> notes) async {
    final c = _config!;
    final uri = _api('/repos/${c.owner}/${c.repo}/contents/${c.path}');
    // 取当前 sha（存在则更新）
    String? sha;
    final head = await http.get(uri, headers: _headers());
    if (head.statusCode == 200) {
      sha = (jsonDecode(head.body) as Map<String, dynamic>)['sha'] as String?;
    }
    final jsonStr = const JsonEncoder.withIndent('  ')
        .convert(notes.map((n) => n.toJson()).toList());
    final resp = await http.put(
      uri,
      headers: _headers(),
      body: jsonEncode({
        'message': 'update notes ${DateTime.now().toIso8601String()}',
        'content': base64Encode(utf8.encode(jsonStr)),
        'branch': c.branch,
        if (sha != null) 'sha': sha,
      }),
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('GitHub 写入失败 (${resp.statusCode}): ${resp.body}');
    }
    await _cacheNotes(notes);
  }
}
