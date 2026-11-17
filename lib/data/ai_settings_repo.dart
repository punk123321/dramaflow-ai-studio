import '../core/gemini_tts.dart';
import 'handoff_repo.dart';

/// App-wide (not per project) settings kept in the local database. The key is
/// stored as plain text inside the app's private storage, is sent only to
/// Gemini, and is not part of a backup.
class AiSettingsRepo {
  static const _projectId = -1;
  static const _kind = 'gemini_tts';
  final _docs = HandoffRepo();

  Future<GeminiTtsSettings> load() async => GeminiTtsSettings.decode(await _docs.getDoc(_projectId, _kind));

  Future<void> save(GeminiTtsSettings s) => _docs.setDoc(_projectId, _kind, s.encode());
}
