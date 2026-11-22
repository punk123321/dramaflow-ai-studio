import '../core/usage_log.dart';
import 'handoff_repo.dart';

/// Today's usage counts and the optional second Gemini model, kept on this
/// phone only (not inside a backup).
class UsageRepo {
  static const _projectId = -1;
  final _docs = HandoffRepo();

  Future<UsageLog> today() async => UsageLog.decode(await _docs.getDoc(_projectId, 'usage_log')).forDay(UsageLog.dayKey(DateTime.now()));

  Future<UsageLog> add({int gemini = 0, int asrSeconds = 0, int voices = 0}) async {
    final now = UsageLog.dayKey(DateTime.now());
    final cur = UsageLog.decode(await _docs.getDoc(_projectId, 'usage_log'));
    final next = cur.add(now, gemini: gemini, asrSeconds: asrSeconds, voices: voices);
    await _docs.setDoc(_projectId, 'usage_log', next.encode());
    return next;
  }

  Future<String> fallbackModel() async => (await _docs.getDoc(_projectId, 'recap_fallback_model') ?? '').trim();

  Future<void> saveFallbackModel(String v) => _docs.setDoc(_projectId, 'recap_fallback_model', v.trim());
}
