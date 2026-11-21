import '../core/news_video.dart';
import 'handoff_repo.dart';

/// Backend address, token and stock-footage key. On this phone only, not in a backup.
class NewsVideoRepo {
  static const _projectId = -1;
  static const _kind = 'news_video';
  final _docs = HandoffRepo();

  Future<NewsVideoSettings> load() async => NewsVideoSettings.decode(await _docs.getDoc(_projectId, _kind));

  Future<void> save(NewsVideoSettings s) => _docs.setDoc(_projectId, _kind, s.encode());
}
