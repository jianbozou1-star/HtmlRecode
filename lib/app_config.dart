// 应用级固定配置：GitHub 仓库与 Token（固定用户方案）。
// Token 不写入源码，由 GitHub Actions 构建时通过
// --dart-define=GH_TOKEN=<secret> 注入（仓库 Settings → Secrets and
// variables → Actions 中配置 GH_TOKEN）。
// 本地调试：flutter run -d chrome --dart-define=GH_TOKEN=github_pat_xxx
class AppConfig {
  static const String owner = 'jianbozou1-star';
  static const String repo = 'HtmlRecode';
  static const String token = String.fromEnvironment('GH_TOKEN');
  static const String branch = 'main';

  static bool get tokenConfigured => token.isNotEmpty;
}
