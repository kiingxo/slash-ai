import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/theme/app_theme.dart';
import 'features/auth/auth_page.dart';

void main() {
  runApp(const ProviderScope(child: SlashApp()));
}

class SlashApp extends StatelessWidget {
  const SlashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '/slash',
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: const AuthPage(),
    );
  }
}
