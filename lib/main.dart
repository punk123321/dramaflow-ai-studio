import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'data/drama_repo.dart';
import 'data/handoff_repo.dart';
import 'data/project_repo.dart';
import 'data/segment_repo.dart';
import 'data/export_item.dart';
import 'state/library_store.dart';
import 'state/render_store.dart';
import 'state/project_store.dart';
import 'ui/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ProjectStore(ProjectRepo(), SegmentRepo(), HandoffRepo())..load(),
        ),
        ChangeNotifierProvider(lazy: false, create: (_) => RenderStore(ExportRepo())),
        ChangeNotifierProvider(
          create: (_) => LibraryStore(DramaRepo())..load(),
        ),
      ],
      child: const DramaFlowApp(),
    ),
  );
}

class DramaFlowApp extends StatelessWidget {
  const DramaFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RGyi Recap — AI Movie Production Studio',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const Shell(),
    );
  }
}
