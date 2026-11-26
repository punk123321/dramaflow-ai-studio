import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/orphan_renders.dart';
import '../data/export_item.dart';
import '../data/handoff_repo.dart';
import '../platform/render_channel.dart';

/// App-wide render state. It listens to the native renderer for the whole life
/// of the app, so a render that finishes while another screen is open is still
/// saved to the export history.
class RenderStore extends ChangeNotifier {
  RenderStore(this._repo) {
    _sub = RenderChannel.events.listen(_onEvent);
    unawaited(adoptFinished());
  }

  final ExportRepo _repo;
  final _docs = HandoffRepo();
  static const _pendingProject = -1;
  static const _pendingKind = 'pending_render';

  Future<void> _setPending(String text) async {
    try {
      await _docs.setDoc(_pendingProject, _pendingKind, text);
    } catch (_) {}
  }

  /// A render that finished while the app was not listening (killed in the background on a long
  /// render, for example) is put into the export history when the app starts again.
  Future<void> adoptFinished() async {
    try {
      final pend = PendingRender.decode(await _docs.getDoc(_pendingProject, _pendingKind));
      if (pend == null) return;
      final files = await RenderChannel.listRenders();
      final f = findFinished(files, pend.name);
      if (f == null) {
        // Nothing was finished. Keep the note only while an unfinished file is still there.
        if (!hasUnfinished(files, pend.name)) await _setPending('');
        return;
      }
      final known = await _repo.forProject(pend.projectId);
      if (!known.any((e) => e.path == f.path)) {
        lastDone = await _repo.insert(ExportItem(
          projectId: pend.projectId,
          name: pend.name,
          path: f.path,
          sizeBytes: f.sizeBytes,
          durationMs: pend.durationMs,
          height: pend.height,
          createdAt: f.modifiedMs,
        ));
      }
      await _setPending('');
      notifyListeners();
    } catch (_) {}
  }
  StreamSubscription<RenderEvent>? _sub;

  int? runningProjectId;
  String _runningName = '';
  int percent = 0;
  String? error;
  bool canceled = false;

  /// The most recent finished render (any project).
  ExportItem? lastDone;

  /// The most recent short test render. It is NOT saved to the export history
  /// and does not count as finishing the Render stage.
  ExportItem? lastSample;
  bool _runningSample = false;

  bool get running => runningProjectId != null;

  Future<void> start(int projectId, String name, Map<String, Object?> job, {bool sample = false}) async {
    if (running) return;
    error = null;
    canceled = false;
    percent = 0;
    runningProjectId = projectId;
    _runningSample = sample;
    _runningName = name;
    notifyListeners();
    if (!sample) {
      await _setPending(PendingRender(
        projectId: projectId,
        name: name,
        height: (job['height'] as num?)?.toInt() ?? 0,
        durationMs: jobDurationMs(job),
      ).encode());
    }
    try {
      await RenderChannel.start(job);
    } on PlatformException catch (e) {
      runningProjectId = null;
      await _setPending('');
      error = switch (e.code) {
        'low_storage' => 'ဖုန်းမှာ နေရာ မလောက်ပါ။ ${e.message ?? ''} ဖိုင်တွေ ဖျက်ပြီး ပြန်စမ်းပါ။',
        'busy' => 'တခြား render တစ်ခု လုပ်နေဆဲပါ။',
        _ => 'Render မစနိုင်ပါ: ${e.message ?? e.code}',
      };
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    if (!running) return;
    try {
      await RenderChannel.cancel();
    } catch (_) {}
  }

  Future<void> _onEvent(RenderEvent e) async {
    switch (e) {
      case RenderProgress():
        percent = e.percent;
      case RenderDone():
        final pid = runningProjectId;
        runningProjectId = null;
        if (pid != null && _runningSample) {
          lastSample = ExportItem(
            projectId: pid,
            name: _runningName,
            path: e.path,
            sizeBytes: e.sizeBytes,
            durationMs: e.durationMs,
            height: e.height,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          );
        } else if (pid != null) {
          try {
            lastDone = await _repo.insert(ExportItem(
              projectId: pid,
              name: _runningName,
              path: e.path,
              sizeBytes: e.sizeBytes,
              durationMs: e.durationMs,
              height: e.height,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ));
          } catch (err) {
            error = 'ဗီဒီယိုထွက်ပြီး ဒါပေမယ့် မှတ်တမ်းသိမ်းလို့မရပါ: $err (ဖိုင်: ${e.path})';
          }
        }
        // The result is recorded (or the error says where the file is), so the note is not needed.
        if (!(pid != null && _runningSample)) await _setPending('');
      case RenderFailed():
        runningProjectId = null;
        await _setPending('');
        error = 'Render မအောင်မြင်ပါ: ${e.message}';
      case RenderCanceled():
        runningProjectId = null;
        await _setPending('');
        canceled = true;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
