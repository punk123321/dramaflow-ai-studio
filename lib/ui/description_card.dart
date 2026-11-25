import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/description_prompt.dart';
import '../core/srt.dart';
import '../core/theme.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../platform/gemini_open.dart';

/// Helps write the YouTube description. The prompt is made from what the app
/// already knows about this project (the narration text and the subtitles) and
/// handed to Gemini; the answer is pasted back here and kept with the project.
/// No API key is needed. The AI reads TEXT only (it does not watch the video),
/// so the description is only as good as the subtitles and must be checked.
class DescriptionCard extends StatefulWidget {
  const DescriptionCard({super.key, required this.project});

  final Project project;

  @override
  State<DescriptionCard> createState() => _DescriptionCardState();
}

class _DescriptionCardState extends State<DescriptionCard> {
  static const _kind = 'yt_description';
  final _repo = HandoffRepo();
  final _title = TextEditingController();
  final _part = TextEditingController();
  final _channel = TextEditingController();
  final _notes = TextEditingController();
  final _result = TextEditingController();
  bool _open = false;
  bool _busy = false;
  String? _msg;
  bool _err = false;

  int get _pid => widget.project.id!;

  @override
  void initState() {
    super.initState();
    _title.text = widget.project.name;
    _loadSaved();
  }

  @override
  void dispose() {
    for (final c in [_title, _part, _channel, _notes, _result]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSaved() async {
    try {
      final t = await _repo.getDoc(_pid, _kind);
      if (t != null && t.isNotEmpty && mounted) setState(() => _result.text = t);
    } catch (_) {}
  }

  void _say(String m, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _msg = m;
      _err = error;
    });
  }

  Future<String> _prompt() async {
    var script = '';
    var sample = '';
    try {
      script = await _repo.getDoc(_pid, DocKind.script) ?? '';
      final studio = await _repo.getDoc(_pid, DocKind.studioSrt);
      final src = (studio != null && studio.trim().isNotEmpty) ? studio : await _repo.getDoc(_pid, DocKind.sourceSrt);
      // With a narration text the subtitles only add times, so they get a smaller share.
      if (src != null && src.trim().isNotEmpty) sample = sampleStory(parseSrt(src).entries, maxChars: script.trim().isEmpty ? 9000 : 3500);
    } catch (_) {}
    return buildDescriptionPrompt(
      title: _title.text,
      part: _part.text,
      channel: _channel.text,
      notes: _notes.text,
      script: script,
      subtitleSample: sample,
    );
  }

  Future<void> _gemini() async {
    setState(() => _busy = true);
    final p = await _prompt();
    final m = await openInGemini(p);
    if (mounted) setState(() => _busy = false);
    _say(m);
  }

  Future<void> _copyPrompt() async {
    final p = await _prompt();
    await Clipboard.setData(ClipboardData(text: p));
    _say('Prompt ကို Copy လုပ်ပြီး။ Gemini (ဒါမှမဟုတ် တခြား AI) ထဲ paste လုပ်ပါ။');
  }

  Future<void> _save() async {
    try {
      await _repo.setDoc(_pid, _kind, _result.text);
      _say('Description ကို project ထဲ သိမ်းပြီး');
    } catch (e) {
      _say('သိမ်းလို့မရပါ: $e', error: true);
    }
  }

  Future<void> _copyResult() async {
    await Clipboard.setData(ClipboardData(text: _result.text));
    await _save();
    _say('Description ကို Copy လုပ်ပြီး၊ project ထဲလည်း သိမ်းပြီး။ YouTube ထဲ paste လုပ်ပါ။');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _open,
          onExpansionChanged: (v) => _open = v,
          title: const Text('YouTube Description ရေး', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Prompt ကို App က ပြင်ပေးမယ် · Gemini ဖြေချက်ကို ဒီမှာ ထည့်', style: TextStyle(fontSize: 12, color: DfColors.muted)),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'ဇာတ်လမ်းအမည်')),
            TextField(controller: _part, decoration: const InputDecoration(labelText: 'အပိုင်း (မလိုရင် ချန်)', hintText: 'Part 3 / Episode 12')),
            TextField(controller: _channel, decoration: const InputDecoration(labelText: 'Channel အမည် (မလိုရင် ချန်)')),
            TextField(controller: _notes, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'ထပ်ဆောင်းမှတ်ချက် (မလိုရင် ချန်)')),
            const SizedBox(height: 6),
            const Text(
              'AI က ဗီဒီယိုပုံကို မကြည့်ပါ၊ ဒီ project ရဲ့ recap စာသားနဲ့ စာတန်းကိုပဲ ဖတ်ပါတယ်။ စာတန်းမရှိရင် ဇာတ်လမ်းအကျဉ်းက မပါဘဲ ထွက်မယ်။ ထွက်လာတာကို ကိုယ်တိုင် စစ်ပါ။',
              style: TextStyle(fontSize: 12, color: DfColors.muted),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              FilledButton.icon(onPressed: _busy ? null : _gemini, icon: const Icon(Icons.auto_awesome, size: 18), label: const Text('Gemini ဖွင့်မယ်')),
              OutlinedButton.icon(onPressed: _busy ? null : _copyPrompt, icon: const Icon(Icons.copy, size: 18), label: const Text('Prompt ကူး')),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _result,
              minLines: 4,
              maxLines: 12,
              decoration: const InputDecoration(labelText: 'Gemini ဖြေချက်ကို ဒီမှာ paste (ပြင်လို့ရ)'),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              FilledButton.tonal(onPressed: _result.text.trim().isEmpty ? null : _copyResult, child: const Text('Description ကူး + သိမ်း')),
              TextButton(onPressed: _save, child: const Text('သိမ်းရုံ')),
            ]),
            if (_msg != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_msg!, style: TextStyle(fontSize: 12.5, color: _err ? DfColors.danger : DfColors.ok)),
              ),
          ],
        ),
      ),
    );
  }
}
