import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/thumbnail_prompt.dart';
import '../data/project.dart';
import '../platform/gemini_open.dart';

/// A prompt for the thumbnail picture of a Chinese xianxia drama recap. The
/// picture is made by an image AI (Gemini, etc.) outside the app; the title text
/// is added afterwards (image AIs cannot write Burmese), so the prompt leaves
/// an empty area for it.
class ThumbnailCard extends StatefulWidget {
  const ThumbnailCard({super.key, required this.project});

  final Project project;

  @override
  State<ThumbnailCard> createState() => _ThumbnailCardState();
}

class _ThumbnailCardState extends State<ThumbnailCard> {
  final _title = TextEditingController();
  final _character = TextEditingController();
  final _scene = TextEditingController();
  ThumbMood _mood = ThumbMood.battle;
  bool _space = true;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _title.text = widget.project.name;
  }

  @override
  void dispose() {
    _title.dispose();
    _character.dispose();
    _scene.dispose();
    super.dispose();
  }

  String _prompt() => buildThumbnailPrompt(title: _title.text, character: _character.text, scene: _scene.text, mood: _mood, leaveTextSpace: _space);

  Future<void> _gemini() async {
    final m = await openInGemini(_prompt());
    if (mounted) setState(() => _msg = m);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _prompt()));
    if (mounted) setState(() => _msg = 'Prompt ကို Copy လုပ်ပြီး။ ပုံထုတ်တဲ့ AI (Gemini စသည်) ထဲ paste လုပ်ပါ။');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const Text('Thumbnail Prompt (Xianxia)', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('ပုံထုတ်တဲ့ AI အတွက် English prompt', style: TextStyle(fontSize: 12, color: DfColors.muted)),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'ဇာတ်လမ်းအမည် (mood အတွက်ပဲ)'), onChanged: (_) => setState(() {})),
            DropdownButtonFormField<ThumbMood>(
              key: ValueKey(_mood),
              initialValue: _mood,
              decoration: const InputDecoration(labelText: 'ခံစားချက်'),
              items: [for (final m in ThumbMood.values) DropdownMenuItem(value: m, child: Text(m.label))],
              onChanged: (v) => setState(() => _mood = v ?? _mood),
            ),
            TextField(
              controller: _character,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'ဇာတ်ကောင် ပုံစံ (English၊ မလိုရင် ချန်)', hintText: 'a cold swordsman in black robes, red eyes, scar on cheek'),
            ),
            TextField(
              controller: _scene,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'မြင်ကွင်း (English၊ မလိုရင် ချန်)', hintText: 'standing on a floating sword above a sea of clouds'),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('ခေါင်းစဉ်ထည့်ဖို့ ဘယ်ဘက် နေရာလွတ်ချန်', style: TextStyle(fontSize: 14)),
              value: _space,
              onChanged: (v) => setState(() => _space = v),
            ),
            const Text(
              'AI ပုံထဲမှာ စာမပါအောင် ပြောထားတယ်၊ မြန်မာစာ ရေးတာ မှန်မှာမဟုတ်လို့ပါ။ ခေါင်းစဉ်ကို ပုံရပြီးနောက် App ရဲ့ thumbnail / Editor စာထည့်တာနဲ့ ထည့်ပါ။ မူရင်း drama ရဲ့ ပုံ၊ ဇာတ်ကောင်ကို မကူးဖို့ prompt ထဲ ပါပြီးသား။',
              style: TextStyle(fontSize: 12, color: DfColors.muted),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              FilledButton.icon(onPressed: _gemini, icon: const Icon(Icons.auto_awesome, size: 18), label: const Text('Gemini ဖွင့်မယ်')),
              OutlinedButton.icon(onPressed: _copy, icon: const Icon(Icons.copy, size: 18), label: const Text('Prompt ကူး')),
            ]),
            if (_msg != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_msg!, style: const TextStyle(fontSize: 12.5, color: DfColors.ok))),
          ],
        ),
      ),
    );
  }
}
