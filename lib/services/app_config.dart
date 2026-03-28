class AppConfig {
  static const String githubOAuthClientId = String.fromEnvironment(
    'GITHUB_OAUTH_CLIENT_ID',
  );

  static const String defaultOpenAIModel = String.fromEnvironment(
    'OPENAI_MODEL',
    defaultValue: 'gpt-4o-mini',
  );

  static const String defaultOpenRouterModel = String.fromEnvironment(
    'OPENROUTER_MODEL',
    defaultValue: 'openai/gpt-4o-mini',
  );

  static bool get hasBundledGitHubClientId =>
      githubOAuthClientId.trim().isNotEmpty;

  static String get missingGitHubOAuthClientIdMessage =>
      'This /slash build is not configured for GitHub sign-in yet. '
      'Add GITHUB_OAUTH_CLIENT_ID when building the app.';
}
