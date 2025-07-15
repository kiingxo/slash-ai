import 'package:flutter/material.dart';
import 'features/repo/repo_page.dart';
import 'features/prompt/prompt_page.dart';

import 'ui/screens/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  static final List<Widget> _pages = <Widget>[
    RepoPage(),
    PromptPage(),
    Center(child: Text('Review (coming soon)', style: TextStyle(fontSize: 24))),
    Center(child: Text('PRs (coming soon)', style: TextStyle(fontSize: 24))),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Repos'),
          BottomNavigationBarItem(icon: Icon(Icons.edit), label: 'Prompt'),
          BottomNavigationBarItem(icon: Icon(Icons.rule), label: 'Review'),
          BottomNavigationBarItem(icon: Icon(Icons.merge_type), label: 'PRs'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
} 