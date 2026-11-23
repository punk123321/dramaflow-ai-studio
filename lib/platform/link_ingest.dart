import '../core/source_link.dart';
import '../core/srt.dart';
import '../data/handoff_repo.dart';
import 'recap_client.dart';

/// Puts the video of a link into the user's own Gemini account through the
/// user's backend, once. The answer (file address + length) is kept with the
/// project, so a retry or the next run reuses it while Gemini still has the
/// file (48 hours) and the link is the same.
class LinkIngest {
  LinkIngest(this._handoff);

  final HandoffRepo _handoff;

  Future<String> linkOf(int projectId) async => (await _handoff.getDoc(projectId, DocKind.sourceLink) ?? '').trim();

  Future<IngestInfo?> cached(int projectId, String url, {int? nowMs}) async {
    final info = IngestInfo.decode(await _handoff.getDoc(projectId, DocKind.ingestInfo));
    if (info == null) return null;
    return info.usableFor(url, nowMs ?? DateTime.now().millisecondsSinceEpoch) ? info : null;
  }

  Future<void> saveLink(int projectId, String url) async {
    await _handoff.setDoc(projectId, DocKind.sourceLink, url.trim());
    // a different link makes the old answer useless
    final old = IngestInfo.decode(await _handoff.getDoc(projectId, DocKind.ingestInfo));
    if (old != null && old.url != url.trim()) await _handoff.setDoc(projectId, DocKind.ingestInfo, '');
  }

  Future<void> clear(int projectId) async {
    await _handoff.setDoc(projectId, DocKind.sourceLink, '');
    await _handoff.setDoc(projectId, DocKind.ingestInfo, '');
  }

  /// The kept answer when it is still good, otherwise download + upload now.
  /// [onStage] gets the backend's stage text and 0..100. [reused] is called
  /// with true when the kept answer was used.
  Future<IngestInfo> ensure({
    required int projectId,
    required RecapClient client,
    required String url,
    required String geminiKey,
    required void Function(String stage, int percent) onStage,
    void Function(bool reused)? reused,
    void Function(int lines, String lang)? onSubs,
  }) async {
    final kept = await cached(projectId, url);
    if (kept != null) {
      reused?.call(true);
      return kept;
    }
    reused?.call(false);
    final info = await client.ingest(url, geminiKey, (j) => onStage(j.stage, j.progress));
    await _handoff.setDoc(projectId, DocKind.ingestInfo, info.encode());
    if (info.srt.isNotEmpty) {
      int n = 0;
      try {
        n = await _saveSubtitles(projectId, info.srt);
      } catch (_) {} // the subtitles are a bonus: they must never fail the link
      if (n > 0) onSubs?.call(n, info.srtLang);
    }
    return info;
  }

  /// Saves the link's own subtitles as the project's source subtitles, only
  /// when the project has none yet (nothing the user made or paid for is
  /// replaced). Returns how many lines were saved, 0 when nothing was.
  Future<int> _saveSubtitles(int projectId, String srt) async {
    for (final kind in [DocKind.studioSrt, DocKind.sourceSrt]) {
      final t = await _handoff.getDoc(projectId, kind);
      if (t != null && t.trim().isNotEmpty && parseSrt(t).entries.isNotEmpty) return 0;
    }
    final entries = parseSrt(srt).entries;
    if (entries.isEmpty) return 0;
    await _handoff.setDoc(projectId, DocKind.sourceSrt, serializeSrt(entries));
    return entries.length;
  }
}
