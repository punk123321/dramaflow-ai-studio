import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'data/drama_repo.dart';
import 'data/project_repo.dart';
import 'data/segment_repo.dart';
import 'state/library_store.dart';
import 'state/project_store.dart';
import 'ui/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ProjectStore(ProjectRepo(), SegmentRepo())..load(),
        ),
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
      title: 'DramaFlow AI Studio',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const Shell(),
    );
  }
}
