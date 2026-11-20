import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fair_use.dart';
import '../core/gemini_tts.dart';
import 'package:path_provider/path_provider.dart';
import '../core/publish_text.dart';
import '../core/theme.dart';
import '../data/ai_settings_repo.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../platform/audio_channel.dart';
import '../platform/gemini_open.dart';
import '../platform/gemini_tts_client.dart';
import '../platform/render_channel.dart';
import 'widgets.dart';

/// Upload helper: titles, description and hashtags written with Gemini by
/// copy/paste (no API key), and a thumbnail made from one frame of the
/// original. Nothing is uploaded or posted by the app.
class PublishScreen extends StatefulWidget {
  const PublishScreen({super.key, required this.project});

  final Project project;

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  final _repo = HandoffRepo();
  final _desc = TextEditingController();
  final _thumbText = TextEditingController();
  final _imgPrompt = TextEditingController();
  GeminiTtsSettings _ai = const GeminiTtsSettings();
  String _aspect = '16:9';
  bool _drawing = false;
  PublishText _text = const PublishText();
  FairUseRecord _fair = const FairUseRecord();
  String _script = '';
  bool _loading = true;
  double _atSec = 0;
  bool _busy = false;
  String? _ownPic;
  String? _thumbPath;
  String? _thumbNote;
  String? _error;

  int get _pid => widget.project.id!;
  double get _maxSec => ((widget.project.videoDurationMs ?? 0) / 1000).clamp(0, 86400).toDouble();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _desc.dispose();
    _thumbText.dispose();
    _imgPrompt.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _text = PublishText.decode(await _repo.getDoc(_pid, DocKind.publishText));
      _fair = FairUseRecord.decode(await _repo.getDoc(_pid, DocKind.fairUse));
      _script = await _repo.getDoc(_pid, DocKind.script) ?? '';
      _desc.text = _text.description;
      _ai = await AiSettingsRepo().load();
      _imgPrompt.text = defaultImagePrompt(widget.project.dramaTitle);
    } catch (e) {
      _error = 'ဖတ်လို့မရပါ: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    _text = PublishText(titles: _text.titles, description: _desc.text, hashtags: _text.hashtags, thumbTexts: _text.thumbTexts);
    await _repo.setDoc(_pid, DocKind.publishText, _text.encode());
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _copyPrompt() async {
    final p = widget.project;
    _toast(await openInGemini(buildPublishPrompt(dramaTitle: p.dramaTitle, episode: p.episode, script: _script)));
  }

  Future<void> _pasteReply() async {
    final c = TextEditingController();
    final reply = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gemini ပြန်ဖြေချက်'),
        content: TextField(
          controller: c,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(hintText: 'ဒီမှာ paste လုပ်ပါ', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final d = await Clipboard.getData('text/plain');
              if (d?.text != null) c.text = d!.text!;
            },
            child: const Text('Paste'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('မလုပ်တော့ဘူး')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('စစ်ပြီး ထည့်မယ်')),
        ],
      ),
    );
    c.dispose();
    if (reply == null) return;
    final parsed = parsePublishReply(reply);
    if (parsed == null) {
      _toast('ဖတ်လို့မရပါ။ Gemini က JSON နဲ့ ပြန်ဖြေထားလား စစ်ပါ။');
      return;
    }
    setState(() {
      _text = parsed;
      _desc.text = parsed.description;
    });
    await _save();
    _toast('ထည့်ပြီးပါပြီ။ ဖတ်ပြီး ကိုယ့်စိတ်ကြိုက် ပြင်ပါ။');
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast('$what ကူးပြီးပါပြီ');
  }

  Future<void> _thumb() async {
    final uri = widget.project.sourceVideoUri;
    if (uri == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await RenderChannel.makeThumbnail(
        videoUri: uri,
        atMs: (_atSec * 1000).round(),
        text: _thumbText.text,
        imagePath: _ownPic,
        name: '${safeName(widget.project.name)}_thumb_${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      );
      _thumbPath = r.path;
      _thumbNote = r.gallery != null ? 'Gallery ထဲ (Pictures/DramaFlow) သိမ်းပြီးပါပြီ။' : 'ဒီ Android မှာ Gallery ထဲ မသိမ်းနိုင်ပါ။ ပုံကို ကြည့်ရုံပဲ ရပါတယ်။';
    } catch (e) {
      _error = 'Thumbnail မထုတ်နိုင်ပါ: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Gemini draws a picture from the prompt (internet, the user's own key, only on tap).
  Future<void> _draw() async {
    setState(() {
      _drawing = true;
      _error = null;
    });
    try {
      final img = await geminiDraw(_ai, _imgPrompt.text.trim(), _aspect);
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/gemini_thumb_${DateTime.now().millisecondsSinceEpoch}.${img.extension}');
      await f.writeAsBytes(img.bytes, flush: true);
      _ownPic = f.path;
      _thumbPath = f.path;
      _thumbNote = 'Gemini ဆွဲထားတဲ့ ပုံပါ။ ကြိုက်ရင် အောက်မှာ စာထည့်ပြီး "ကိုယ့်ပုံကို သိမ်းမယ်" နှိပ်ပါ။ မကြိုက်ရင် ထပ်ဆွဲခိုင်းပါ။';
    } catch (e) {
      _error = e is GeminiTtsException ? e.message : 'ဆွဲလို့မရပါ: $e';
    }
    if (mounted) setState(() => _drawing = false);
  }

  Future<void> _pickOwn() async {
    try {
      final f = await AudioChannel.pickImage();
      if (f != null) setState(() => _ownPic = f);
    } catch (e) {
      setState(() => _error = 'ပုံ ရွေးမရပါ: $e');
    }
  }

  String safeName(String s) {
    final c = s.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
    return c.isEmpty ? 'dramaflow' : (c.length > 40 ? c.substring(0, 40) : c);
  }

  @override
  Widget build(BuildContext context) {
    final credit = uploadNote(_fair, dramaTitle: widget.project.dramaTitle);
    return DfScaffold(
      appBar: AppBar(title: const Text('Upload & Thumbnail')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'ဒီ app က ဘာမှ မတင်ပေးပါဘူး။ စာသားတွေကို ကူးပြီး ကိုယ်တိုင် တင်ရတာပါ။ Gemini ရေးတာကို ဖတ်ပြီး မှန်ရဲ့လား စစ်ပါ။',
                  style: TextStyle(color: DfColors.muted, fontSize: 13),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: DfColors.danger, fontSize: 13)),
                ],
                const SectionTitle('ခေါင်းစဉ် / description / hashtag'),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _copyPrompt, icon: const Icon(Icons.open_in_new, size: 18), label: const Text('Gemini ဖွင့်မယ်'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(onPressed: _pasteReply, icon: const Icon(Icons.paste, size: 18), label: const Text('Gemini ပြန်ဖြေ'))),
                ]),
                if (_script.trim().isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Narration script မရှိသေးလို့ Gemini က ဇာတ်ကားနာမည်နဲ့ပဲ ရေးရမယ်။', style: TextStyle(color: DfColors.warn, fontSize: 12.5)),
                  ),
                const SizedBox(height: 10),
                for (final t in _text.titles)
                  Card(
                    child: ListTile(
                      dense: true,
                      title: Text(t),
                      trailing: const Icon(Icons.copy, size: 18),
                      onTap: () => _copy(t, 'ခေါင်းစဉ်'),
                    ),
                  ),
                if (_text.titles.isNotEmpty || _text.description.isNotEmpty) ...[
                  TextField(
                    controller: _desc,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: maxDescriptionChars,
                    decoration: const InputDecoration(labelText: 'Description (ပြင်လို့ရတယ်)', border: OutlineInputBorder()),
                    onEditingComplete: _save,
                  ),
                  if (_text.hashtags.isNotEmpty) Text(_text.hashtags.join(' '), style: const TextStyle(color: DfColors.muted, fontSize: 13)),
                  const SizedBox(height: 6),
                  const Text('မူရင်းရင်းမြစ်စာသား (Copyright & Fair Use မှာ ဖြည့်ထားတာ)', style: TextStyle(color: DfColors.muted, fontSize: 12)),
                  Text(credit, style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      await _save();
                      await _copy(finalDescription(_text, credit), 'Description အပြည့်အစုံ');
                    },
                    icon: const Icon(Icons.copy_all, size: 18),
                    label: const Text('Description အပြည့် ကူးမယ် (+ ရင်းမြစ် + hashtag)'),
                  ),
                ],
                const SectionTitle('Thumbnail'),
                const Text('မူရင်းဗီဒီယိုထဲက frame တစ်ခုကို ယူပြီး စာထည့်မယ်။ မူရင်းဗီဒီယိုကို မပြင်ပါဘူး။', style: TextStyle(color: DfColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Gemini ကို ပုံဆွဲခိုင်းမယ်', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  children: [
                    TextField(
                      controller: _imgPrompt,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(labelText: 'ဘာဆွဲခိုင်းမလဲ (ပြင်လို့ရ)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, children: [
                      for (final a in imageAspects)
                        ChoiceChip(label: Text(a), selected: _aspect == a, onSelected: (_) => setState(() => _aspect = a)),
                    ]),
                    const SizedBox(height: 6),
                    const Text('နည်း ၁ — Gemini app (chat) နဲ့၊ API key မလိုပါ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 4),
                    FilledButton.icon(
                      onPressed: () async {
                        final msg = await openInGemini('${_imgPrompt.text.trim()}\nMake the picture $_aspect shaped.');
                        _toast('$msg ပုံထွက်ရင် Gemini ထဲမှာ သိမ်း (Download) ပြီး ပြန်လာ၊ အောက်က "ကိုယ်တိုင်ဒီဇိုင်းဆွဲထားတဲ့ ပုံ ရွေးမယ်" ကို နှိပ်ပါ။');
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Gemini app ဖွင့်ပြီး ဆွဲခိုင်းမယ်'),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'ပုံထွက်လာရင် Gemini ထဲမှာ သိမ်းပါ။ ပြီးရင် ဒီ app က "ကိုယ်တိုင်ဒီဇိုင်းဆွဲထားတဲ့ ပုံ ရွေးမယ်" နဲ့ ရွေးပြီး စာထည့်၊ သိမ်းလို့ရတယ်။ '
                      'Gemini app ထဲမှာ ပုံဆွဲခွင့် ရှိမရှိက ကိုယ့် account ပေါ် မူတည်တယ်။',
                      style: TextStyle(fontSize: 11.5, color: DfColors.muted),
                    ),
                    const SizedBox(height: 10),
                    Text('နည်း ၂ — API နဲ့ (app ထဲမှာ တန်းဆွဲ)${_ai.ready ? '' : ' · key မရှိသေး'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    if (!_ai.ready)
                      const Text('API key ကို Stage 3 → Audio → "Gemini API အသံ" မှာ ထည့်ပါ (key တစ်ခုတည်းကို သုံးတယ်)။', style: TextStyle(color: DfColors.warn, fontSize: 12)),
                    const SizedBox(height: 4),
                    FilledButton.tonalIcon(
                      onPressed: (!_ai.ready || _drawing || _busy) ? null : _draw,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: Text(_drawing ? 'ဆွဲနေတယ်...' : 'API နဲ့ ဆွဲမယ်'),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                        'နည်း ၂ နှိပ်တဲ့အခါ အပေါ်က prompt စာသားကို Google ဆီ internet နဲ့ ပို့ပါတယ်။ ကိုယ့် key ရဲ့ သုံးခွင့်/ကုန်ကျစရိတ် ကျတယ်။ '
                        'ဇာတ်ကားထဲက တကယ့်ဇာတ်ဆောင်၊ ဇာတ်ကောင်၊ logo ကို အတိအကျ ဆွဲခိုင်းတာမျိုး မလုပ်ပါနဲ့၊ ကိုယ်ပိုင်ပုံစံပဲ ခိုင်းပါ။ '
                        'ထွက်လာတဲ့ ပုံက ကိုယ်ပိုင်မူပိုင်ခွင့် ကိစ္စ ကင်းတယ်လို့ ကျွန်တော် အာမခံလို့ မရပါဘူး၊ တင်ခင် ကိုယ်တိုင်ကြည့်ပါ။ '
                        'ဒါကို Google ကို တကယ်မခေါ်ကြည့်ရသေးလို့ error ပေါ်ရင် စာကို ပြောပြပါ။',
                        style: TextStyle(fontSize: 11.5, color: DfColors.muted),
                      ),
                    ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickOwn,
                  icon: const Icon(Icons.brush_outlined, size: 18),
                  label: Text(_ownPic == null ? 'ကိုယ်တိုင်ဒီဇိုင်းဆွဲထားတဲ့ ပုံ ရွေးမယ်' : 'ကိုယ့်ပုံ ရွေးပြီး (ပြန်ရွေးလို့ရ)'),
                ),
                if (_ownPic != null)
                  TextButton(onPressed: _busy ? null : () => setState(() => _ownPic = null), child: const Text('ကိုယ့်ပုံ မသုံးတော့ဘူး (ဗီဒီယို frame သုံးမယ်)')),
                if (_ownPic != null)
                  const Text(
                    'ကိုယ့်ပုံကို ကူးပြီး Gallery (Pictures/DramaFlow) ထဲ သိမ်းပေးမယ်။ မူရင်းပုံကို မပြင်ပါဘူး။ ပုံပေါ်ကစာ ထည့်ချင်ရင် အောက်မှာ ရေးပါ၊ မထည့်ရင် ဗလာထားပါ။ ဒီပုံကို YouTube/Facebook မှာ ကိုယ်တိုင် upload တင်ပါ။',
                    style: TextStyle(color: DfColors.muted, fontSize: 12),
                  ),
                if (_ownPic == null && _maxSec <= 0)
                  const Padding(padding: EdgeInsets.only(top: 6), child: Text('ဗီဒီယို အရှည် မသိသေးပါ။ Project မှာ ဗီဒီယို ရွေးပါ။', style: TextStyle(color: DfColors.warn, fontSize: 13)))
                else ...[
                  if (_ownPic == null) ...[
                    Slider(
                      value: _atSec.clamp(0, _maxSec),
                      max: _maxSec,
                      onChanged: _busy ? null : (v) => setState(() => _atSec = v),
                    ),
                    Text('အချိန် ${_atSec.toStringAsFixed(1)} စက္ကန့်', style: const TextStyle(fontSize: 13)),
                  ],
                  if (_text.thumbTexts.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    const Text('Gemini အကြံပေး စာတန်း (နှိပ်ရင် ထည့်ပေးမယ်)', style: TextStyle(color: DfColors.muted, fontSize: 12)),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final t in _text.thumbTexts)
                        ActionChip(label: Text(t, style: const TextStyle(fontSize: 12.5)), onPressed: () => setState(() => _thumbText.text = t)),
                    ]),
                  ] else
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('အလန်းစား စာတန်း လိုချင်ရင် အပေါ်က Gemini ဖွင့်မယ် → ဖြေပြီးရင် Gemini ပြန်ဖြေ ထဲ ထည့်ပါ။', style: TextStyle(color: DfColors.muted, fontSize: 12)),
                    ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _thumbText,
                    maxLength: 60,
                    decoration: const InputDecoration(labelText: 'ပုံပေါ်က စာ (မထည့်လည်းရ)', border: OutlineInputBorder()),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _thumb,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: Text(_busy ? 'ထုတ်နေတယ်...' : (_ownPic == null ? 'Thumbnail ထုတ်မယ်' : 'ကိုယ့်ပုံကို သိမ်းမယ်')),
                  ),
                ],
                if (_thumbPath != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(File(_thumbPath!))),
                  if (_thumbNote != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_thumbNote!, style: const TextStyle(fontSize: 12.5))),
                ],
              ],
            ),
    );
  }
}
