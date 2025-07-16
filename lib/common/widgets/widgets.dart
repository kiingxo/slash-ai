// Common widgets for the app will go here. 
String friendlyErrorMessage(dynamic error) {
  final msg = error?.toString() ?? '';
  if (msg.contains('GitHub PAT not found')) {
    return 'GitHub authentication is required. Please log in again.';
  }
  if (msg.contains('Missing API keys')) {
    return 'API keys are missing. Please log in again.';
  }
  if (msg.contains('Failed to fetch files')) {
    return 'Could not fetch files from GitHub. Please check your connection and token.';
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
    return 'Your GitHub token is invalid or expired. Please log in again.';
  }
  if (msg.isEmpty) {
    return 'An unknown error occurred.';
  }
  // Fallback: generic message
  return 'Something went wrong. Please try again.';
} 