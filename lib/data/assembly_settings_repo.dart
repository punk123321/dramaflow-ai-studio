import '../core/assembly.dart';
import 'handoff_repo.dart';

/// The AssemblyAI key and language. Stored like the Gemini key: on this phone
/// only, not inside a backup.
class AssemblySettingsRepo {
  static const _projectId = -1;
  static const _kind = 'assemblyai';
  final _docs = HandoffRepo();

  Future<AssemblySettings> load() async => AssemblySettings.decode(await _docs.getDoc(_projectId, _kind));

  Future<void> save(AssemblySettings s) => _docs.setDoc(_projectId, _kind, s.encode());
}
