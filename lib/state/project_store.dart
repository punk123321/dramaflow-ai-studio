import 'package:flutter/foundation.dart';

import '../core/stage.dart';
import '../data/project.dart';
import '../data/project_repo.dart';

/// App-wide project state. Every change is written to SQLite first, then
/// reflected in memory, so closing and reopening the app restores it.
class ProjectStore extends ChangeNotifier {
  ProjectStore(this._repo);

  final ProjectRepo _repo;

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
  }) async {
    final now = _now();
    await _run(() async {
      final saved = await _repo.insert(Project(
        name: name,
        dramaTitle: dramaTitle,
        episode: episode,
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

  Future<void> duplicate(Project p) async {
    final now = _now();
    await _run(() async {
      final copy = Project(
        name: '${p.name} (ကူး)',
        dramaTitle: p.dramaTitle,
        episode: p.episode,
        doneMask: p.doneMask,
        sourceVideoUri: p.sourceVideoUri,
        createdAt: now,
        updatedAt: now,
      );
      final saved = await _repo.insert(copy);
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

  Future<void> _replace(Project updated) async {
    await _run(() async {
      await _repo.update(updated);
      final next = items.map((x) => x.id == updated.id ? updated : x).toList();
      next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      items = next;
    });
  }
}
