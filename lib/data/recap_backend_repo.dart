import '../core/news_video.dart';
import 'handoff_repo.dart';
import 'news_video_repo.dart';

/// The address and token of the RECAP backend (Video/Scene Recap, the voice in
/// the Audio stage, the queue). It used to share one slot with News Video,
/// which have different backends, so it has its own slot now. On this phone
/// only, not in a backup.
class RecapBackendRepo {
  static const _projectId = -1;
  static const _kind = 'recap_backend';
  final _docs = HandoffRepo();

  /// The first time, the address that was saved in the shared slot is copied
  /// here once, so nobody has to connect again.
  Future<NewsVideoSettings> load() async {
    final own = await _docs.getDoc(_projectId, _kind);
    if (own != null && own.trim().isNotEmpty) return NewsVideoSettings.decode(own);
    final old = await NewsVideoRepo().load();
    if (old.ready) {
      try {
        await save(old);
      } catch (_) {}
    }
    return old;
  }

  Future<void> save(NewsVideoSettings s) => _docs.setDoc(_projectId, _kind, s.encode());
}
