import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'widgets.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'workflow_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(
            onOpenWorkflow: () => setState(() => _index = 1),
            onOpenLibrary: () => setState(() => _index = 2),
          ),
          const WorkflowScreen(),
          const LibraryScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: DfNavBar(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
        items: const [
          (icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
          (icon: Icons.account_tree_outlined, activeIcon: Icons.account_tree_rounded, label: 'Workflow'),
          (icon: Icons.video_library_outlined, activeIcon: Icons.video_library_rounded, label: 'Library'),
          (icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, label: 'Settings'),
        ],
      ),
    );
  }
}
