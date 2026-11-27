import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/colab_render.dart';
import '../core/studio.dart';
import '../core/theme.dart';
import '../data/project.dart';
import '../data/recap_backend_repo.dart';
import '../platform/audio_channel.dart';
import '../platform/background_work.dart';
import '../platform/render_channel.dart';
import '../platform/studio_client.dart';

/// Make the video on the Colab machine (its GPU) instead of the phone, so the phone stays cool.
/// Stage 1: only the simple parts of an edit are supported; anything else is refused with the reasons,
/// never silently left out. The video must already be in the backend's library (Studio > Download / Drive library).
class ColabRenderCard extends StatefulWidget {
  const ColabRenderCard({super.key, required this.project, required this.buildJob, required this.busyElsewhere});

  final Project project;

  /// Builds the render job for the given output name (same job the phone would render).
  final Map<String, Object?> Function(String name) buildJob;

  /// True while the phone itself is rendering.
  final bool busyElsewhere;

  @override
  State<ColabRenderCard> createState() => _ColabRenderCardState();
}

class _ColabRenderCardState extends State<ColabRenderCard> {
  List<StudioFile> _videos = [];
  String? _pick;
  bool _loaded = false;
  bool _listing = false;
  bool _busy = false;
  String? _jobId;
  StudioClient? _client;
  String _stage = '';
  int _pct = 0;
  String? _msg;
  bool _err = false;
  String? _outName; // finished file in the backend's library
  bool _saving = false;
  String _transfer = '';

  Future<StudioClient?> _connect() async {
    final s = await RecapBackendRepo().load();
    if (!s.ready) {
      setState(() {
        _msg = 'Colab backend ချိတ်ထားတာ မရှိသေးဘူး (Studio / Settings ထဲမှာ URL#TOKEN ထည့်ပါ)';
        _err = true;
      });
      return null;
    }
    return StudioClient(s);
  }

  Future<void> _refresh() async {
    if (_listing || _busy) return;
    setState(() {
      _listing = true;
      _msg = null;
    });
    try {
      final c = await _connect();
      if (c == null) return;
      final lib = await c.library();
      final v = lib.ofKind('video')..sort((a, b) => b.mtime.compareTo(a.mtime));
      if (!mounted) return;
      setState(() {
        _videos = v;
        _loaded = true;
        if (_pick == null || !v.any((f) => f.name == _pick)) _pick = v.isEmpty ? null : v.first.name;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = 'Library ဖတ်မရဘူး: $e';
          _err = true;
        });
      }
    } finally {
      if (mounted) setState(() => _listing = false);
    }
  }

  Future<void> _run() async {
    final file = _pick;
    if (file == null || _busy) return;
    final name = 'colab_${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final Map<String, Object?> job;
    try {
      job = widget.buildJob(name);
    } catch (e) {
      setState(() {
        _msg = 'Job ပြင်လို့ မရဘူး: $e';
        _err = true;
      });
      return;
    }
    final why = colabUnsupported(job);
    if (why.isNotEmpty) {
      setState(() {
        _msg = 'Colab မှာ မထုတ်သေးဘူး (ဗီဒီယိုမှာ ပျက်မသွားအောင် ငြင်းထားတာ):\n• ${why.join('\n• ')}\n\nဖုန်းမှာပဲ ထုတ်ပါ၊ ဒါမှမဟုတ် အဲဒီအပိုင်းတွေ ဖယ်ပါ။';
        _err = true;
      });
      return;
    }
    final c = await _connect();
    if (c == null) return;
    _client = c;
    setState(() {
      _busy = true;
      _msg = null;
      _err = false;
      _outName = null;
      _stage = 'စတင်နေတယ်';
      _pct = 0;
      _jobId = null;
    });
    await BackgroundWork.begin('DramaFlow · Colab မှာ ထုတ်နေတယ်', 'စတင်နေတယ်');
    try {
      final done = await c.run(studioRenderRequest(file: file, job: job), (j) {
        BackgroundWork.update('Colab: ${j.stage}', percent: j.progress);
        if (mounted) {
          setState(() {
            _stage = j.stage;
            _pct = j.progress;
          });
        }
      }, onId: (id) => _jobId = id);
      if (done.state == StudioState.done && done.files.isNotEmpty) {
        setState(() {
          _outName = done.files.first;
          _msg = 'Colab မှာ ထုတ်ပြီး ✓ (${done.files.first})${done.notes.isEmpty ? '' : '\n${done.notes.join('\n')}'}';
          _err = false;
        });
      } else if (done.state == StudioState.canceled) {
        setState(() {
          _msg = 'ရပ်လိုက်ပြီ';
          _err = false;
        });
      } else {
        setState(() {
          _msg = 'Colab မှာ မအောင်ဘူး: ${done.error.isEmpty ? done.errors.join('\n') : done.error}';
          _err = true;
        });
      }
    } on StudioCanceled {
      if (mounted) setState(() => _msg = 'ရပ်လိုက်ပြီ');
    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = '$e';
          _err = true;
        });
      }
    } finally {
      _client = null;
      await BackgroundWork.end();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final id = _jobId;
    final c = _client;
    if (c == null) return;
    try {
      if (id != null) await c.control(id, 'cancel');
    } catch (_) {}
    c.cancel();
  }

  Future<void> _toPhone() async {
    final name = _outName;
    if (name == null || _saving) return;
    final c = await _connect();
    if (c == null) return;
    setState(() {
      _saving = true;
      _msg = null;
      _transfer = '';
    });
    await BackgroundWork.begin('DramaFlow · ဖိုင် ဖုန်းထဲ ယူနေတယ်', 'စတင်နေတယ်');
    final tmp = File('${Directory.systemTemp.path}/colab_${DateTime.now().millisecondsSinceEpoch}.mp4');
    try {
      await c.downloadFile(name, tmp, (got, total) {
        final pct = total > 0 ? (got * 100 / total).round() : 0;
        BackgroundWork.update('ဖုန်းထဲ ယူနေတယ်', percent: pct);
        if (mounted) setState(() => _transfer = '${formatBytes(got)}${total > 0 ? ' / ${formatBytes(total)} ($pct%)' : ''}');
      });
      final base = name.toLowerCase().endsWith('.mp4') ? name.substring(0, name.length - 4) : name;
      try {
        await RenderChannel.saveToGallery(tmp.path, base);
      } on PlatformException catch (e) {
        if (e.code != 'use_export') rethrow;
        await AudioChannel.export(tmp.path, name, 'video/mp4');
      }
      if (mounted) {
        setState(() {
          _msg = 'Gallery (Movies/DramaFlow) ထဲ သိမ်းပြီး ✓';
          _err = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = 'ဖုန်းထဲ မရဘူး: $e';
          _err = true;
        });
      }
    } finally {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      await BackgroundWork.end();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.project.videoSize;
    StudioFile? picked;
    for (final f in _videos) {
      if (f.name == _pick) picked = f;
    }
    final same = picked == null ? null : sameVideoSize(size, picked.size);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: ExpansionTile(
        leading: const Icon(Icons.cloud_outlined),
        title: const Text('Colab မှာ ထုတ်မယ် (ဖုန်းမပူအောင်)', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('အဆင့် ၁ — ရိုးရိုး edit သာ', style: TextStyle(fontSize: 12.5, color: DfColors.muted)),
        onExpansionChanged: (open) {
          if (open && !_loaded) _refresh();
        },
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ပါတာ: ဖြတ်တာ (အစီအစဉ်အတိုင်း), speed, flip, blur, Censor box, မူရင်းအသံ, စာတန်းထည့်ထုတ်, အရွယ်/fit (မူရင်း/bars/crop), fps, bitrate။\n'
            'မပါသေးတာ: Narration, Music, Overlay, Split, Logo, Crop/Zoom, Filter, Freeze, Blur-background — ပါနေရင် ငြင်းမယ် (ပျောက်ပြီး မထုတ်ဘူး)။\n'
            'ဗီဒီယိုက Colab library ထဲ မူရင်းဖိုင်အတိုင်း ရှိပြီးသား ဖြစ်ရမယ်။',
            style: TextStyle(fontSize: 12.5, color: DfColors.muted),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _videos.isEmpty
                  ? Text(_listing ? 'ဖတ်နေတယ် …' : (_loaded ? 'Library ထဲ ဗီဒီယို မရှိဘူး' : ''), style: const TextStyle(fontSize: 13))
                  : DropdownButton<String>(
                      isExpanded: true,
                      value: _pick,
                      items: [
                        for (final f in _videos) DropdownMenuItem(value: f.name, child: Text('${f.name} · ${formatBytes(f.size)}', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: _busy ? null : (v) => setState(() => _pick = v),
                    ),
            ),
            IconButton(onPressed: (_listing || _busy) ? null : _refresh, icon: const Icon(Icons.refresh), tooltip: 'Library ပြန်ဖတ်'),
          ]),
          if (same == false)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('⚠ ဒီဖိုင်ရဲ့ size က project ဗီဒီယိုနဲ့ မတူဘူး — တခြားဖိုင်ဖြစ်နေနိုင်တယ်၊ အချိန်တွေ မကိုက်ရင် ပုံမှားမယ်။', style: TextStyle(fontSize: 12.5, color: DfColors.danger)),
            ),
          if (_busy) ...[
            LinearProgressIndicator(value: _pct > 0 ? _pct / 100 : null),
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('$_stage${_pct > 0 ? ' · $_pct%' : ''}', style: const TextStyle(fontSize: 12.5))),
            OutlinedButton(onPressed: _stop, child: const Text('ရပ်မယ်')),
          ] else
            FilledButton.icon(
              onPressed: (_pick == null || widget.busyElsewhere || _saving) ? null : _run,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: Text(widget.busyElsewhere ? 'ဖုန်း render လုပ်နေဆဲ' : 'Colab မှာ ထုတ်မယ်'),
            ),
          if (_outName != null && !_busy)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.tonalIcon(
                onPressed: _saving ? null : _toPhone,
                icon: const Icon(Icons.phone_android, size: 18),
                label: Text(_saving ? 'ယူနေတယ် $_transfer' : 'ဖုန်းထဲ (Gallery) ယူမယ်'),
              ),
            ),
          if (_saving) const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator()),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_msg!, style: TextStyle(fontSize: 12.5, color: _err ? DfColors.danger : DfColors.ok)),
            ),
        ],
      ),
    );
  }
}
