import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../repo/repo_controller.dart';
import 'project_service.dart';

final projectWindowProvider = StateProvider<ProjectWindow>(
  (_) => ProjectWindow.sevenDays,
);

final projectOverviewProvider = FutureProvider<ProjectOverview>((ref) async {
  final repoState = ref.watch(repoControllerProvider);
  final authState = ref.watch(authControllerProvider);
  final repo =
      repoState.selectedRepo ??
      (repoState.repos.isNotEmpty ? repoState.repos.first : null);

  if (repo == null) {
    throw Exception('Select a repository to generate a project summary.');
  }

  final githubAccessToken = authState.githubAccessToken?.trim();
  if (githubAccessToken == null || githubAccessToken.isEmpty) {
    throw Exception('GitHub authentication is required.');
  }

  return ProjectInsightsService.load(
    repo: repo,
    window: ref.watch(projectWindowProvider),
    githubAccessToken: githubAccessToken,
    model: authState.model,
    openAIApiKey: authState.openAIApiKey,
    openAIModel: authState.openAIModel,
    openRouterApiKey: authState.openRouterApiKey,
    openRouterModel: authState.openRouterModel,
  );
});
