import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/scenes.dart';
import '../core/segments.dart';
import '../core/srt.dart';
import '../core/theme.dart';
import '../core/video_recap.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../data/segment_repo.dart';
import '../platform/scene_channel.dart';
import 'widgets.dart';

/// Scene Recap: the phone finds the scenes and makes a numbered contact sheet;
/// Gemini gets one small picture plus the dialogue text instead of the whole
/// video, and writes the narration scene by scene. No API, no key.
class SceneRecapScreen extends StatefulWidget {
  const SceneRecapScreen({super.key, required this.project});

  final Project project;

  @override
  State<SceneRecapScreen> createState() => _SceneRecapScreenState();
}

class _SceneRecapScreenState extends State<SceneRecapScreen> {
  static const _task = 'srecap';
  final _repo = HandoffRepo();
  final _segRepo = SegmentRepo();
  final _reply = TextEditingController();
  final _notes = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  List<SrtEntry> _srt = [];
  List<SceneSpan> _scenes = [];
  Map<int, String> _texts = {};
  final Map<int, SheetResult> _sheets = {};
  int _stepSec = 1;
  int _maxScenes = 40;
  bool _loading = true;
  bool _analyzing = false;
  bool _cancel = false;
  double _progress = 0;
  String? _msg;
  bool _err = false;

  int get _pid => widget.project.id!;
  int get _durationMs => widget.project.videoDurationMs ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancel = true;
    _reply.dispose();
    _notes.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _say(String m, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _msg = m;
      _err = error;
    });
  }

  Future<void> _load() async {
    final studio = await _repo.getDoc(_pid, DocKind.studioSrt);
    final src = (studio != null && studio.trim().isNotEmpty) ? studio : await _repo.getDoc(_pid, DocKind.sourceSrt);
    _srt = src == null ? [] : parseSrt(src).entries;
    _notes.text = await _repo.getDoc(_pid, DocKind.notes) ?? '';
    _texts = await _repo.results(_pid, _task);
    final plan = await _repo.getDoc(_pid, DocKind.scenePlan);
    if (plan != null) {
      try {
        final l = jsonDecode(plan) as List;
        _scenes = [for (final e in l) SceneSpan((e as List)[0] as int, e[1] as int)];
      } catch (_) {
        _scenes = [];
      }
    }
    _from.text = formatTime(0);
    _to.text = formatTime(_durationMs);
    _stepSec = _durationMs > 600000 ? 2 : 1;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _savePlan() => _repo.setDoc(_pid, DocKind.scenePlan, jsonEncode([for (final s in _scenes) [s.startMs, s.endMs]]));

  Future<void> _analyze() async {
    final p = widget.project;
    if (!p.hasVideo || p.sourceVideoUri == null) {
      _say('ဗီဒီယို မရွေးရသေးပါ (Stage 1)။', error: true);
      return;
    }
    final a = parseTime(_from.text) ?? 0;
    final b = parseTime(_to.text) ?? _durationMs;
    final end = _durationMs > 0 && b > _durationMs ? _durationMs : b;
    if (end - a < 3000) {
      _say('အကွာအဝေး မမှန်ပါ (အနည်းဆုံး ၃ စက္ကန့်)။', error: true);
      return;
    }
    setState(() {
      _analyzing = true;
      _cancel = false;
      _progress = 0;
      _msg = null;
      _sheets.clear();
    });
    try {
      final stepMs = _stepSec * 1000;
      final times = <int>[];
      final bytes = BytesBuilder(copy: false);
      const chunk = 120;
      var t = a;
      while (t < end) {
        if (_cancel || !mounted) {
          _say('ရပ်လိုက်တယ်။');
          setState(() => _analyzing = false);
          return;
        }
        final to = t + chunk * stepMs < end ? t + chunk * stepMs : end;
        final r = await SceneChannel.analyze(p.sourceVideoUri!, t, to, stepMs);
        if (r.timesMs.isEmpty) break;
        times.addAll(r.timesMs);
        bytes.add(r.sigs);
        t = to;
        if (mounted) setState(() => _progress = (t - a) / (end - a));
      }
      final diffs = diffSeries(bytes.takeBytes());
      final scenes = pickScenes(timesMs: times, diffs: diffs, rangeStartMs: a, rangeEndMs: end, maxScenes: _maxScenes);
      _scenes = scenes;
      _texts = {};
      for (final k in (await _repo.results(_pid, _task)).keys) {
        await _repo.deleteResult(_pid, _task, k);
      }
      await _savePlan();
      _say('Scene ${scenes.length} ခု တွေ့ပြီ။ မှားနေတဲ့ ဖြတ်တောက်မှုကို "ပေါင်း" နဲ့ ဖယ်နိုင်တယ်။');
    } on PlatformException catch (e) {
      _say('Scene မခွဲနိုင်ပါ: ${e.message}', error: true);
    } catch (e) {
      _say('Scene မခွဲနိုင်ပါ: $e', error: true);
    }
    if (mounted) setState(() => _analyzing = false);
  }

  Future<void> _merge(int i) async {
    setState(() {
      _scenes = mergeWithPrevious(_scenes, i);
      _sheets.clear();
    });
    await _savePlan();
  }

  List<String> get _dialogue => [for (final s in _scenes) dialogueFor(_srt, s)];

  String _prompt(int from, int to) => buildSceneRecapPrompt(
        dramaTitle: widget.project.dramaTitle,
        episode: widget.project.episode,
        scenes: _scenes,
        dialogue: _dialogue,
        from: from,
        to: to,
        notes: _notes.text,
      );

  Future<void> _sheetAndGemini((int, int) g) async {
    final p = widget.project;
    try {
      final key = g.$1;
      final stamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final sheet = await SceneChannel.contactSheet(p.sourceVideoUri!, _scenes.sublist(g.$1 - 1, g.$2), g.$1, 'scenes_${_pid}_${key}_$stamp');
      setState(() => _sheets[key] = sheet);
      final prompt = _prompt(g.$1, g.$2);
      await Clipboard.setData(ClipboardData(text: prompt));
      final r = await SceneChannel.shareImage(sheet.gallery, prompt);
      _say(switch (r) {
        'gemini' => 'Gemini ပွင့်ပြီး ပုံနဲ့ prompt ပို့ပြီ။ ဖြေပြီးရင် ဖြေချက်ကို copy လုပ်ပြီး ပြန်လာပါ။',
        'chooser' => 'Gemini app မတွေ့လို့ share စာရင် ဖွင့်ထားတယ်။ Gemini ကို ရွေးပါ။ (Prompt ကူးထားပြီး)',
        _ => 'ဒီဖုန်း (Android 9 နှင့်အောက်) က ပုံကို တိုက်ရိုက်မပို့နိုင်ပါ။ Prompt ကူးထားပြီး၊ Gemini မှာ ပုံကို ကိုယ်တိုင် ထည့်ပါ။',
      });
    } on PlatformException catch (e) {
      _say('Contact sheet မလုပ်နိုင်ပါ: ${e.message}', error: true);
    } catch (e) {
      _say('Contact sheet မလုပ်နိုင်ပါ: $e', error: true);
    }
  }

  Future<void> _copyOnly((int, int) g) async {
    await Clipboard.setData(ClipboardData(text: _prompt(g.$1, g.$2)));
    _say('Prompt ကူးပြီး။');
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
    for (final e in r.entries) {
      if (e.key > _scenes.length) continue;
      await _repo.saveResult(_pid, _task, e.key, e.value);
      saved++;
    }
    _texts = await _repo.results(_pid, _task);
    _reply.clear();
    _say('Scene $saved ခု သိမ်းပြီး။');
  }

  Future<void> _saveAll() async {
    final map = {for (final e in _texts.entries) if (e.key <= _scenes.length) e.key: e.value};
    if (map.isEmpty) {
      _say('သိမ်းစရာ script မရှိသေးဘူး။', error: true);
      return;
    }
    final old = await _repo.getDoc(_pid, DocKind.script);
    if (old != null && old.trim().isNotEmpty && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Script နဲ့ Video Index အစားထိုးမလား?'),
          content: const Text('အဆင့် ၃ မှာ ရှိပြီးသား narration script နဲ့ Video Index ကို အခု scene တွေနဲ့ အစားထိုးမယ်။'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('မလုပ်ဘူး')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('အစားထိုးမယ်')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _repo.setDoc(_pid, DocKind.script, scriptFromParts(map));
    await _segRepo.replaceAll(_pid, toSegments(_scenes));
    final missing = [for (var i = 1; i <= _scenes.length; i++) if (!map.containsKey(i)) i];
    _say('Script (scene ${map.length} ခု) နဲ့ Video Index သိမ်းပြီး။ အဆင့် ၃ မှာ အသံလုပ်၊ Editor မှာ "Video Index က ယူ" နဲ့ "ဗီဒီယိုကို အသံအတိုင်း ညှိ" သုံးပါ။'
        '${missing.isEmpty ? '' : '\nscript မပါသေးတဲ့ scene: ${missing.join(', ')} (အသံနဲ့ အပိုင်း အစဉ်မကိုက်နိုင်ဘူး)'}');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return DfScaffold(appBar: AppBar(title: const Text('Scene Recap')), body: const Center(child: CircularProgressIndicator()));
    final has = widget.project.hasVideo && widget.project.sourceVideoUri != null;
    final groups = sheetGroups(_scenes.length);
    return DfScaffold(
      appBar: AppBar(title: const Text('Scene Recap')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
          'ဖုန်းက scene တွေကို ရှာပြီး scene တစ်ခုကို ပုံ ၁ ပုံ၊ နံပါတ်နဲ့ အချိန်တပ်ထားတဲ့ ပုံတစ်ချပ် (contact sheet) လုပ်ပေးတယ်။ Gemini ကို ဗီဒီယိုတစ်ခုလုံး မပို့ဘဲ ဒီပုံ + စာတန်းစာသားပဲ ပို့တာမို့ token သက်သာတယ်။ '
          'အသံကို Gemini မကြားရဘူး၊ ဒါကြောင့် စာတန်း (SRT) ရှိရင် ပိုမှန်တယ်။ မူရင်းဗီဒီယိုကို မပြင်ပါဘူး။',
          style: TextStyle(color: DfColors.muted, fontSize: 13),
        ),
        if (!has) const Padding(padding: EdgeInsets.only(top: 12), child: Text('ဗီဒီယို မရွေးရသေးဘူး (Stage 1)။', style: TextStyle(color: DfColors.danger))),
        if (has) ...[
          SectionTitle(_srt.isEmpty ? '၁။ Scene ခွဲ (စာတန်း မရှိသေး: ပုံကိုပဲ အားကိုးရမယ်)' : '၁။ Scene ခွဲ (စာတန်း ${_srt.length} ကြောင်းနဲ့ တွဲမယ်)'),
          Row(children: [
            Expanded(child: TextField(controller: _from, enabled: !_analyzing, decoration: const InputDecoration(labelText: 'စ (m:ss)'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _to, enabled: !_analyzing, decoration: const InputDecoration(labelText: 'ဆုံး (m:ss)'))),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('နမူနာယူချိန်'),
            DropdownButton<int>(
              value: _stepSec,
              items: const [
                DropdownMenuItem(value: 1, child: Text('၁ စက္ကန့်စီ (တိကျ၊ နှေး)')),
                DropdownMenuItem(value: 2, child: Text('၂ စက္ကန့်စီ')),
                DropdownMenuItem(value: 4, child: Text('၄ စက္ကန့်စီ (မြန်)')),
              ],
              onChanged: _analyzing ? null : (v) => setState(() => _stepSec = v ?? 1),
            ),
            const Text('Scene အများဆုံး'),
            DropdownButton<int>(
              value: _maxScenes,
              items: const [20, 40, 60, 80].map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(),
              onChanged: _analyzing ? null : (v) => setState(() => _maxScenes = v ?? 40),
            ),
          ]),
          const SizedBox(height: 8),
          if (_analyzing) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 4),
            Text('စစ်နေတယ် ${(_progress * 100).round()}% (app ဖွင့်ထားပါ)', style: const TextStyle(fontSize: 13)),
            OutlinedButton(onPressed: () => setState(() => _cancel = true), child: const Text('ရပ်မယ်')),
          ] else
            FilledButton.icon(onPressed: _analyze, icon: const Icon(Icons.content_cut, size: 18), label: Text(_scenes.isEmpty ? 'Scene ခွဲမယ်' : 'ပြန်ခွဲမယ်')),
          if (_scenes.isNotEmpty) ...[
            SectionTitle('၂။ Scene ${_scenes.length} ခု'),
            for (var i = 0; i < _scenes.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                title: Text('${formatTime(_scenes[i].startMs)} – ${formatTime(_scenes[i].endMs)}'),
                subtitle: Text(_dialogue[i].isEmpty ? '(စာတန်း မရှိ)' : _dialogue[i], maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: i == 0 ? null : TextButton(onPressed: () => _merge(i), child: const Text('ပေါင်း')),
              ),
            const SectionTitle('၃။ Gemini ကို ပို့'),
            const Text('အုပ်စုတစ်ခုချင်း (scene ၁၂ ခုစီ) ပို့ပါ။ ပုံနဲ့ prompt ကို Gemini ဆီ တစ်ခါတည်း ပို့မယ်၊ prompt ကိုလည်း ကူးထားမယ်။', style: TextStyle(color: DfColors.muted, fontSize: 12)),
            for (final g in groups) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                FilledButton.icon(onPressed: () => _sheetAndGemini(g), icon: const Icon(Icons.open_in_new, size: 18), label: Text('Scene ${g.$1}–${g.$2} · Gemini ဖွင့်')),
                OutlinedButton(onPressed: () => _copyOnly(g), child: const Text('Prompt ကူး')),
              ]),
              if (_sheets[g.$1] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_sheets[g.$1]!.path), fit: BoxFit.fitWidth)),
                ),
            ],
            const SectionTitle('၄။ Gemini ဖြေချက် ပြန်ထည့်'),
            TextField(controller: _reply, minLines: 3, maxLines: 8, decoration: const InputDecoration(hintText: '=== PART 1 === ...')),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: _paste, child: const Text('Paste')),
              FilledButton(onPressed: _read, child: const Text('ဖတ်ပြီး scene အလိုက်သိမ်း')),
            ]),
            SectionTitle('သိမ်းပြီးသား ${_texts.length}/${_scenes.length}'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 1; i <= _scenes.length; i++) Chip(label: Text('$i'), avatar: Icon(_texts.containsKey(i) ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: _texts.containsKey(i) ? DfColors.ok : DfColors.muted)),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'နာမည်/စကားလုံး မှတ်ချက် (prompt ထဲ ပါမယ်)'),
              onChanged: (v) => _repo.setDoc(_pid, DocKind.notes, v),
            ),
            const SectionTitle('၅။ Project ထဲ သိမ်း'),
            FilledButton.icon(onPressed: _saveAll, icon: const Icon(Icons.save_alt, size: 18), label: const Text('Script + Video Index အဖြစ် သိမ်း')),
          ],
        ],
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_msg!, style: TextStyle(color: _err ? DfColors.danger : DfColors.ok, fontSize: 13))),
      ]),
    );
  }
}
