import 'package:flutter/foundation.dart';

import '../core/segments.dart';
import '../core/stage.dart';
import '../data/project.dart';
import '../data/handoff_repo.dart';
import '../data/project_repo.dart';
import '../data/segment_repo.dart';
import '../data/video_info.dart';

/// App-wide project state. Every change is written to SQLite first, then
/// reflected in memory, so closing and reopening the app restores it.
class ProjectStore extends ChangeNotifier {
  ProjectStore(this._repo, this._segRepo, [this._handoff]);

  final ProjectRepo _repo;
  final SegmentRepo _segRepo;
  final HandoffRepo? _handoff;

  List<Project> items = [];
  int? currentId;
  bool freeMode = false;
  bool loading = true;
  String? error;

  Project? get current {
    for (final p in items) {
      if (p.id == currentId) return p;
    }
    return null;
  }

  /// Most recently touched project that is not finished.
  Project? get resumeCandidate {
    for (final p in items) {
      if (!p.finished) return p;
    }
    return null;
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      items = await _repo.all();
      error = null;
    } catch (e) {
      error = 'Project များကို ဖတ်မရပါဘူး။ App ကို ပိတ်ပြီး ပြန်ဖွင့်ကြည့်ပါ။';
    }
    loading = false;
    notifyListeners();
  }

  Future<bool> _run(Future<void> Function() job) async {
    try {
      await job();
      error = null;
      notifyListeners();
      return true;
    } catch (e) {
      error = 'မသိမ်းနိုင်ခဲ့ပါဘူး။ ဖုန်းမှာ နေရာ လုံလောက်မလား စစ်ပြီး ထပ်စမ်းပါ။';
      notifyListeners();
      return false;
    }
  }

  void open(Project p) {
    currentId = p.id;
    notifyListeners();
  }

  void setFreeMode(bool v) {
    freeMode = v;
    notifyListeners();
  }

  Future<void> create({
    required String name,
    required String dramaTitle,
    required int episode,
    int? dramaId,
  }) async {
    final now = _now();
    await _run(() async {
      final saved = await _repo.insert(Project(
        name: name,
        dramaTitle: dramaTitle,
        episode: episode,
        dramaId: dramaId,
        createdAt: now,
        updatedAt: now,
      ));
      items = [saved, ...items];
      currentId = saved.id;
    });
  }

  Future<void> rename(Project p, String name) async {
    await _replace(p.copyWith(name: name, updatedAt: _now()));
  }

  /// Copies the project, including its video link and video index.
  Future<void> duplicate(Project p) async {
    final now = _now();
    await _run(() async {
      final base = p.copyWith(name: '${p.name} (ကူး)', updatedAt: now);
      final saved = await _repo.insert(Project(
        name: base.name,
        dramaTitle: base.dramaTitle,
        episode: base.episode,
        doneMask: base.doneMask,
        sourceVideoUri: base.sourceVideoUri,
        dramaId: base.dramaId,
        videoName: base.videoName,
        videoSize: base.videoSize,
        videoDurationMs: base.videoDurationMs,
        videoWidth: base.videoWidth,
        videoHeight: base.videoHeight,
        videoThumb: base.videoThumb,
        createdAt: now,
        updatedAt: now,
      ));
      if (p.id != null && saved.id != null) {
        final segs = await _segRepo.load(p.id!);
        if (segs.isNotEmpty) await _segRepo.replaceAll(saved.id!, segs);
        await _handoff?.copyProject(p.id!, saved.id!);
      }
      items = [saved, ...items];
    });
  }

  Future<void> delete(Project p) async {
    final id = p.id;
    if (id == null) return;
    await _run(() async {
      await _repo.delete(id);
      items = items.where((x) => x.id != id).toList();
      if (currentId == id) currentId = null;
    });
  }

  Future<void> setStageDone(Project p, Stage s, bool done) async {
    await _replace(p.withStage(s, done, _now()));
  }

  /// Attaches a picked video and clears the old video index, because the old
  /// time ranges belong to the previous video.
  Future<void> attachVideo(Project p, VideoInfo v) async {
    final id = p.id;
    if (id == null) return;
    await _run(() async {
      final updated = p.withVideo(v, _now());
      await _segRepo.replaceAll(id, const []);
      await _repo.update(updated);
      _swap(updated);
    });
  }

  Future<List<SegmentSpec>> segmentsOf(Project p) async {
    final id = p.id;
    if (id == null) return const [];
    return _segRepo.load(id);
  }

  /// Saves the whole video index and marks the Video index stage done when
  /// there is at least one segment.
  Future<bool> saveSegments(Project p, List<SegmentSpec> specs) async {
    final id = p.id;
    if (id == null) return false;
    return _run(() async {
      await _segRepo.replaceAll(id, specs);
      final updated = p.withStage(Stage.videoIndex, specs.isNotEmpty, _now());
      await _repo.update(updated);
      _swap(updated);
    });
  }

  Future<void> _replace(Project updated) async {
    await _run(() async {
      await _repo.update(updated);
      _swap(updated);
    });
  }

  void _swap(Project updated) {
    final next = items.map((x) => x.id == updated.id ? updated : x).toList();
    next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    items = next;
  }
}
