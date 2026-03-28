// Common widgets for the app will go here. 
String friendlyErrorMessage(dynamic error) {
  final msg = error?.toString() ?? '';
  if (msg.contains('GitHub authentication')) {
    return 'GitHub sign-in is required. Connect your account and try again.';
  }
  if (msg.contains('Missing API keys')) {
    return 'Your AI provider settings are incomplete. Check OpenAI or OpenRouter and try again.';
  }
  if (msg.contains('Failed to fetch files')) {
    return 'Could not fetch files from GitHub. Check your connection and repository access.';
  }
  if (msg.contains('Unexpected response from GitHub API')) {
    return 'GitHub returned an unexpected response. Please try again.';
  }
  if (msg.contains('This is a file, not a directory.')) {
    return 'You selected a file, not a folder.';
  }
  if (msg.contains('SocketException')) {
    return 'Network error. Please check your internet connection.';
  }
  if (msg.contains('401') || msg.contains('Unauthorized')) {
    return 'Your GitHub session expired. Sign in again and retry.';
  }
  if (msg.isEmpty) {
    return 'An unknown error occurred.';
  }
  // Fallback: generic message
  return 'Something went wrong. Please try again.';
} 
