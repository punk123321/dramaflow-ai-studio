import 'package:aistudio/core/theme.dart';
import 'package:aistudio/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _items = <({IconData icon, IconData activeIcon, String label})>[
  (icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
  (icon: Icons.account_tree_outlined, activeIcon: Icons.account_tree_rounded, label: 'Workflow'),
  (icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, label: 'Settings'),
];

Widget _app(Widget home) => MaterialApp(theme: buildTheme(), home: home);

void main() {
  testWidgets('DfNavBar stays a bar at the bottom and leaves the page its space', (t) async {
    // This is the bug the first Aurora build had: the bar grew to the whole
    // screen and the page had no room left.
    var index = 0;
    await t.pumpWidget(_app(StatefulBuilder(builder: (c, set) {
      return Scaffold(
        body: const Center(child: Text('PAGE', key: Key('page'))),
        bottomNavigationBar: DfNavBar(index: index, onChanged: (i) => set(() => index = i), items: _items),
      );
    })));
    await t.pumpAndSettle();

    final screen = t.view.physicalSize / t.view.devicePixelRatio;
    final bar = t.getRect(find.byType(DfNavBar));
    expect(bar.height, lessThan(100));
    expect(bar.bottom, closeTo(screen.height, 1));
    expect(t.getRect(find.byKey(const Key('page'))).center.dy, lessThan(bar.top));
  });

  testWidgets('DfNavBar: the chosen tab shows its name, tapping another moves it', (t) async {
    var index = 0;
    await t.pumpWidget(_app(StatefulBuilder(builder: (c, set) {
      return Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: DfNavBar(index: index, onChanged: (i) => set(() => index = i), items: _items),
      );
    })));
    await t.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);

    await t.tap(find.byIcon(Icons.settings_outlined));
    await t.pumpAndSettle();
    expect(index, 2);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('DfScaffold shows its body and the bottom bar together', (t) async {
    await t.pumpWidget(_app(DfScaffold(
      appBar: AppBar(title: const Text('T')),
      body: const Center(child: Text('BODY')),
      bottomNavigationBar: DfNavBar(index: 0, onChanged: (_) {}, items: _items),
    )));
    await t.pumpAndSettle();
    expect(find.text('BODY'), findsOneWidget);
    expect(t.getRect(find.text('BODY')).bottom, lessThan(t.getRect(find.byType(DfNavBar)).top));
  });

  testWidgets('GradientButton calls back when enabled and not when disabled', (t) async {
    var n = 0;
    await t.pumpWidget(_app(Scaffold(body: Column(children: [
      GradientButton(label: 'ON', icon: Icons.add, onPressed: () => n++),
      const GradientButton(label: 'OFF', icon: Icons.add, onPressed: null),
    ]))));
    await t.tap(find.text('ON'));
    await t.tap(find.text('OFF'));
    expect(n, 1);
  });

  testWidgets('Reveal, Glass, GlowChip, Pressable build inside a scrolling list', (t) async {
    var taps = 0;
    await t.pumpWidget(_app(DfScaffold(
      body: ListView(children: [
        Reveal(child: Glass(child: const Text('G'))),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 2,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisExtent: 90),
          itemBuilder: (_, i) => Reveal(index: i, child: Pressable(onTap: () => taps++, child: GlowChip(icon: Icons.mic, color: DfColors.cyan))),
        ),
      ]),
    )));
    await t.pumpAndSettle();
    expect(find.text('G'), findsOneWidget);
    await t.tap(find.byType(GlowChip).first);
    expect(taps, 1);
    expect(t.takeException(), isNull);
  });
}
