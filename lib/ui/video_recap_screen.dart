import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/segments.dart';
import '../core/theme.dart';
import '../core/video_recap.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../data/segment_repo.dart';
import '../platform/gemini_open.dart';
import 'widgets.dart';

/// Gemini watches the video (the user attaches it in the Gemini app) and writes
/// the narration part by part. This app only prepares the prompt, reads the
/// reply back, and saves it as the narration script. No API, no key.
class VideoRecapScreen extends StatefulWidget {
  const VideoRecapScreen({super.key, required this.project});

  final Project project;

  @override
  State<VideoRecapScreen> createState() => _VideoRecapScreenState();
}

class _VideoRecapScreenState extends State<VideoRecapScreen> {
  static const _task = 'vrecap';
  final _repo = HandoffRepo();
  final _segRepo = SegmentRepo();
  final _reply = TextEditingController();
  final _notes = TextEditingController();
  List<SegmentSpec> _parts = [];
  bool _fromIndex = false;
  Map<int, String> _texts = {};
  int _batch = 0; // 0-based batch number
  static const _perBatch = 5;
  bool _loading = true;
  String? _msg;
  bool _err = false;

  int get _pid => widget.project.id!;
  int get _batches => (_parts.length / _perBatch).ceil();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _say(String m, {bool error = false}) => setState(() {
        _msg = m;
        _err = error;
      });

  Future<void> _load() async {
    var segs = await _segRepo.load(_pid);
    _fromIndex = segs.isNotEmpty;
    if (segs.isEmpty) segs = buildSegments(widget.project.videoDurationMs ?? 0, 60000);
    _texts = await _repo.results(_pid, _task);
    _notes.text = await _repo.getDoc(_pid, DocKind.notes) ?? '';
    if (mounted) {
      setState(() {
        _parts = segs;
        _loading = false;
      });
    }
  }

  String _prompt() {
    final from = _batch * _perBatch + 1;
    final to = (_batch + 1) * _perBatch;
    return buildVideoRecapPrompt(
      dramaTitle: widget.project.dramaTitle,
      episode: widget.project.episode,
      parts: _parts,
      from: from,
      to: to > _parts.length ? _parts.length : to,
      notes: _notes.text,
    );
  }

  Future<void> _open() async {
    final m = await openInGemini(_prompt());
    _say('$m\nGemini ထဲမှာ ဗီဒီယိုကို ဒီ chat မှာ တစ်ခါတည်း ထည့်ပါ (📎)၊ ပြီးမှ send နှိပ်ပါ။');
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _prompt()));
    _say('Prompt ကူးပြီး။ Gemini မှာ ဗီဒီယိုထည့်ပြီး paste လုပ်ပါ။');
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) setState(() => _reply.text = d!.text!);
  }

  Future<void> _read() async {
    final r = parseVideoRecapReply(_reply.text);
    if (r.isEmpty) {
      _say('"=== PART 1 ===" ပုံစံ အပိုင်းတွေ မတွေ့ဘူး။ Gemini ရဲ့ အဖြေအကုန်ကို ကူးထားလား စစ်ပါ။', error: true);
      return;
    }
    var saved = 0;
    final bad = <int>[];
    for (final e in r.entries) {
      if (e.key > _parts.length) {
        bad.add(e.key);
        continue;
      }
      await _repo.saveResult(_pid, _task, e.key, e.value);
      saved++;
    }
    _texts = await _repo.results(_pid, _task);
    _reply.clear();
    _say('အပိုင်း $saved ခု သိမ်းပြီး။${bad.isEmpty ? '' : ' (အပိုင်း ${bad.join(', ')} က စာရင်းထဲ မရှိလို့ ချန်ထားတယ်)'}');
  }

  Future<void> _saveScript() async {
    final map = {for (final e in _texts.entries) if (e.key <= _parts.length) e.key: e.value};
    if (map.isEmpty) {
      _say('သိမ်းစရာ အပိုင်း မရှိသေးဘူး။', error: true);
      return;
    }
    final old = await _repo.getDoc(_pid, DocKind.script);
    if (old != null && old.trim().isNotEmpty && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Script အစားထိုးမလား?'),
          content: const Text('အဆင့် ၃ မှာ ရှိပြီးသား narration script ကို အခု အပိုင်းတွေနဲ့ အစားထိုးမယ်။'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('မလုပ်ဘူး')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('အစားထိုးမယ်')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _repo.setDoc(_pid, DocKind.script, scriptFromParts(map));
    if (!_fromIndex) {
      await _segRepo.replaceAll(_pid, _parts);
      _fromIndex = true;
    }
    final missing = [for (var i = 1; i <= _parts.length; i++) if (!map.containsKey(i)) i];
    _say('Script သိမ်းပြီး (အပိုင်း ${map.length} ခု)။ အဆင့် ၃ မှာ အသံလုပ်ပါ၊ Editor မှာ "Video Index က ယူ" နဲ့ "ဗီဒီယိုကို အသံအတိုင်း ညှိ" သုံးပါ။'
        '${missing.isEmpty ? '' : '\nမပါသေးတဲ့ အပိုင်း: ${missing.join(', ')} (ပါမှ အသံနဲ့ အပိုင်း အစဉ်မကိုက်နိုင်ဘူး)'}');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return DfScaffold(appBar: AppBar(title: const Text('Video Recap')), body: const Center(child: CircularProgressIndicator()));
    final has = widget.project.hasVideo && _parts.isNotEmpty;
    return DfScaffold(
      appBar: AppBar(title: const Text('Video Recap (Gemini က ဗီဒီယိုကြည့်ပြီး ရေး)')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const InfoHint(
          'ဒီ app က ဗီဒီယိုကို Gemini ဆီ မပို့ပေးဘူး။ Gemini app ထဲမှာ ဗီဒီယိုကို ကိုယ်တိုင် ထည့်ရမယ် (📎)။ '
          'App က အပိုင်းအလိုက် prompt ပြင်ပေး၊ အဖြေကို ပြန်ဖတ်ပေးတာပဲ။ Gemini က ဗီဒီယိုကို မှားနားလည်နိုင်လို့ ထွက်လာတာကို ကိုယ်တိုင် ဖတ်စစ်ပါ။',
          label: 'ဘယ်လိုအလုပ်လုပ်လဲ',
        ),
        if (!has)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('ဗီဒီယို မရွေးရသေးဘူး (Stage 1)။', style: TextStyle(color: DfColors.danger)),
          )
        else ...[
          SectionTitle('အပိုင်း ${_parts.length} ခု ${_fromIndex ? '(Video Index က)' : '(၁ မိနစ်စီ အလိုအလျောက်)'}'),
          TextField(
            controller: _notes,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'နာမည်/စကားလုံး မှတ်ချက် (မဖြစ်မနေ မဟုတ်)'),
            onChanged: (v) => _repo.setDoc(_pid, DocKind.notes, v),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('အုပ်စု:'),
            DropdownButton<int>(
              value: _batch,
              items: [
                for (var i = 0; i < _batches; i++)
                  DropdownMenuItem(value: i, child: Text('အပိုင်း ${i * _perBatch + 1}–${((i + 1) * _perBatch).clamp(1, _parts.length)}')),
              ],
              onChanged: (v) => setState(() => _batch = v ?? 0),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton.icon(onPressed: _open, icon: const Icon(Icons.open_in_new, size: 18), label: const Text('Gemini ဖွင့်မယ်')),
            OutlinedButton.icon(onPressed: _copy, icon: const Icon(Icons.copy, size: 18), label: const Text('Prompt ကူး')),
          ]),
          const SectionTitle('Gemini ဖြေချက် ပြန်ထည့်'),
          TextField(controller: _reply, minLines: 3, maxLines: 8, decoration: const InputDecoration(hintText: '=== PART 1 === ...')),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            OutlinedButton(onPressed: _paste, child: const Text('Paste')),
            FilledButton(onPressed: _read, child: const Text('ဖတ်ပြီး အပိုင်းခွဲသိမ်း')),
          ]),
          SectionTitle('သိမ်းပြီးသား ${_texts.length}/${_parts.length}'),
          for (var i = 1; i <= _parts.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_texts.containsKey(i) ? Icons.check_circle : Icons.radio_button_unchecked, color: _texts.containsKey(i) ? DfColors.ok : DfColors.muted, size: 20),
              title: Text('အပိုင်း $i · ${formatTime(_parts[i - 1].startMs)}–${formatTime(_parts[i - 1].endMs)}'),
              subtitle: _texts.containsKey(i) ? Text(_texts[i]!, maxLines: 2, overflow: TextOverflow.ellipsis) : null,
            ),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _saveScript, icon: const Icon(Icons.save_alt, size: 18), label: const Text('Narration script အဖြစ် သိမ်း')),
        ],
        if (_msg != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(_msg!, style: TextStyle(color: _err ? DfColors.danger : DfColors.ok, fontSize: 13))),
      ]),
    );
  }
}
