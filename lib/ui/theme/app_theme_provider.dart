import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:slash_flutter/services/cache_storage_service.dart';

import 'app_theme.dart';

final appThemeProvider = NotifierProvider<AppThemeNotifier, AppTheme>(
  AppThemeNotifier.new,
);

class AppThemeNotifier extends Notifier<AppTheme> {
  AppTheme _currentTheme = AppTheme.dark();

  @override
  AppTheme build() {
    bool darkTheme = CacheStorage.fetchBool("darkTheme") ?? false;
    final theme = darkTheme ? AppTheme.dark() : _currentTheme;
    return theme;
  }

  void setDarkMode() {
    state = AppTheme.dark();
    _currentTheme = AppTheme.dark();
    CacheStorage.save("darkTheme", true);
  }

  void setLightMode() {
    state = AppTheme.light();
    _currentTheme = AppTheme.light();
    CacheStorage.save("darkTheme", false);
  }
}
