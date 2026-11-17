import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'library_screen.dart';
import 'placeholder_screen.dart';
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
    final destinations = const [
      NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
      NavigationDestination(icon: Icon(Icons.account_tree_outlined), selectedIcon: Icon(Icons.account_tree), label: 'Workflow'),
      NavigationDestination(icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library), label: 'Library'),
      NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
    ];
    final pages = [
      HomeScreen(
        onOpenWorkflow: () => setState(() => _index = 1),
        onOpenLibrary: () => setState(() => _index = 2),
      ),
      const WorkflowScreen(),
      const LibraryScreen(),
      const PlaceholderScreen(title: 'Settings', phase: 4),
    ];

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 850) {
            return Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  extended: constraints.maxWidth >= 1200,
                  labelType: constraints.maxWidth >= 1200
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: BrandMark(size: 42),
                  ),
                  destinations: [
                    for (final d in destinations)
                      NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: IndexedStack(index: _index, children: pages)),
              ],
            );
          }
          return IndexedStack(index: _index, children: pages);
        },
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 850
          ? NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: destinations,
            )
          : null,
    );
  }
}
