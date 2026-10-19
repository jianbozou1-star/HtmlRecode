// 应用级固定配置：GitHub 仓库与 Token（固定用户方案）。
// 注意：Token 会打包进网页代码，任何访问者可见，请使用仅针对该仓库
// 的最小权限 fine-grained token（Contents: Read and write）。
class AppConfig {
  static const String owner = 'jianbozou1-star';
  static const String repo = 'HtmlRecode';
  static const String token = 'YOUR_GITHUB_TOKEN_HERE'; // TODO: 在这里填入你的 Token
  static const String branch = 'main';

  static bool get tokenConfigured =>
      token.isNotEmpty && token != 'YOUR_GITHUB_TOKEN_HERE';
}
