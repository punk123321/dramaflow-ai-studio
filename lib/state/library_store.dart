import 'package:flutter/foundation.dart';

import '../data/drama.dart';
import '../data/drama_repo.dart';

enum LibraryFilter { all, ongoing, done, none }

class LibraryStore extends ChangeNotifier {
  LibraryStore(this._repo);

  final DramaRepo _repo;

  List<Drama> dramas = [];
  List<Episode> episodes = [];
  bool loading = true;
  String? error;
  String query = '';
  LibraryFilter filter = LibraryFilter.all;

  int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      dramas = await _repo.allDramas();
      episodes = await _repo.allEpisodes();
      error = null;
    } catch (e) {
      error = 'ဇာတ်လမ်းစာရင်းကို ဖတ်မရပါဘူး။ App ကို ပိတ်ပြီး ပြန်ဖွင့်ကြည့်ပါ။';
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

  List<Episode> episodesOf(int dramaId) =>
      episodes.where((e) => e.dramaId == dramaId).toList();

  Drama? byId(int? id) {
    if (id == null) return null;
    for (final d in dramas) {
      if (d.id == id) return d;
    }
    return null;
  }

  DramaStatus statusOf(Drama d) => dramaStatus(episodesOf(d.id!));

  /// Search over Chinese title, Burmese title and description, then the
  /// status filter.
  List<Drama> get filtered {
    final q = query.trim().toLowerCase();
    return dramas.where((d) {
      if (q.isNotEmpty) {
        final hay = '${d.titleZh} ${d.titleMy} ${d.description}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      final s = statusOf(d);
      switch (filter) {
        case LibraryFilter.all:
          return true;
        case LibraryFilter.ongoing:
          return s == DramaStatus.ongoing;
        case LibraryFilter.done:
          return s == DramaStatus.done;
        case LibraryFilter.none:
          return s == DramaStatus.none;
      }
    }).toList();
  }

  void setQuery(String v) {
    query = v;
    notifyListeners();
  }

  void setFilter(LibraryFilter f) {
    filter = f;
    notifyListeners();
  }

  Future<void> addDrama({
    required String titleZh,
    required String titleMy,
    required String description,
    required int season,
  }) async {
    final now = _now();
    await _run(() async {
      final saved = await _repo.insertDrama(Drama(
        titleZh: titleZh,
        titleMy: titleMy,
        description: description,
        season: season,
        createdAt: now,
        updatedAt: now,
      ));
      dramas = [saved, ...dramas];
    });
  }

  Future<void> updateDrama(
    Drama d, {
    required String titleZh,
    required String titleMy,
    required String description,
    required int season,
  }) async {
    final updated = d.copyWith(
      titleZh: titleZh,
      titleMy: titleMy,
      description: description,
      season: season,
      updatedAt: _now(),
    );
    await _run(() async {
      await _repo.updateDrama(updated);
      dramas = dramas.map((x) => x.id == updated.id ? updated : x).toList();
    });
  }

  Future<void> deleteDrama(Drama d) async {
    final id = d.id;
    if (id == null) return;
    await _run(() async {
      await _repo.deleteDrama(id);
      dramas = dramas.where((x) => x.id != id).toList();
      episodes = episodes.where((e) => e.dramaId != id).toList();
    });
  }

  /// Returns an error message, or null when the episode was added.
  Future<String?> addEpisode(
    int dramaId, {
    required int number,
    required int durationMin,
    required String source,
  }) async {
    final exists = episodes.any((e) => e.dramaId == dramaId && e.number == number);
    if (exists) return 'အပိုင်း $number ကို ထည့်ပြီးသားပါ။';
    final ok = await _run(() async {
      final saved = await _repo.insertEpisode(Episode(
        dramaId: dramaId,
        number: number,
        durationMin: durationMin,
        source: source,
      ));
      episodes = [...episodes, saved]
        ..sort((a, b) {
          final c = a.dramaId.compareTo(b.dramaId);
          return c != 0 ? c : a.number.compareTo(b.number);
        });
    });
    return ok ? null : error;
  }

  Future<void> setEpisodeCompleted(Episode e, bool done) async {
    final updated = e.copyWith(completed: done);
    await _run(() async {
      await _repo.updateEpisode(updated);
      episodes = episodes.map((x) => x.id == updated.id ? updated : x).toList();
    });
  }

  Future<void> deleteEpisode(Episode e) async {
    final id = e.id;
    if (id == null) return;
    await _run(() async {
      await _repo.deleteEpisode(id);
      episodes = episodes.where((x) => x.id != id).toList();
    });
  }
}
