import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/srt.dart';
import '../core/te_ai.dart';
import '../core/te_suggest.dart';
import '../core/theme.dart';
import '../core/timeline.dart';
import '../core/transformative_plan.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../platform/audio_channel.dart';

/// TE-1: a separate, persisted planning workspace. Actual effect rendering is
/// added in later TE phases through the existing timeline and Render Center.
class TransformativeEditorScreen extends StatefulWidget {
  const TransformativeEditorScreen({super.key, required this.project});

  final Project project;

  @override
  State<TransformativeEditorScreen> createState() => _TransformativeEditorScreenState();
}

class _TransformativeEditorScreenState extends State<TransformativeEditorScreen> {
  final _repo = HandoffRepo();
  final _instructions = TextEditingController();
  TransformativePlan _plan = const TransformativePlan();
  String _savedSnapshot = '';
  Timeline _timeline = const Timeline();
  bool _loading = true;
  bool _saving = false;
  String? _message;
  String? _error;

  int get _projectId => widget.project.id!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rawPlan = await _repo.getDoc(_projectId, DocKind.transformativePlan);
      final rawTimeline = await _repo.getDoc(_projectId, DocKind.timeline);
      _plan = TransformativePlan.decode(rawPlan);
      _timeline = Timeline.decode(rawTimeline);
      _instructions.text = _plan.instructions;
      _savedSnapshot = _plan.copyWith(instructions: _plan.instructions.trim()).encode();
    } catch (e) {
      _error = 'TE အချက်အလက် ဖတ်မရပါ: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
      _error = null;
    });
    try {
      final next = _plan.copyWith(instructions: _instructions.text.trim());
      await _repo.setDoc(_projectId, DocKind.transformativePlan, next.encode());
      if (!mounted) return;
      setState(() {
        _plan = next;
        _savedSnapshot = next.encode();
        _message = 'TE Plan ကို သိမ်းပြီးပါပြီ။';
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'သိမ်းမရပါ: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  TransformativePlan get _current => _plan.copyWith(instructions: _instructions.text.trim());

  bool get _dirty => !_loading && _current.encode() != _savedSnapshot;

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('မသိမ်းရသေးပါ'),
        content: const Text('ပြင်ထားတာတွေ မသိမ်းရသေးပါ။ ထွက်ရင် ပျောက်သွားမယ်။'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ဆက်ပြင်မယ်')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('မသိမ်းဘဲ ထွက်မယ်')),
        ],
      ),
    );
    return leave ?? false;
  }

  Future<void> _copyPrompt() async {
    final raw = await _repo.getDoc(_projectId, DocKind.studioSrt);
    final src = (raw != null && raw.trim().isNotEmpty) ? raw : (await _repo.getDoc(_projectId, DocKind.sourceSrt) ?? '');
    final prompt = buildTePrompt(
      projectName: widget.project.name,
      sourceMs: widget.project.videoDurationMs ?? 0,
      subtitles: src,
      instructions: _instructions.text,
      tools: _plan.enabledTools,
    );
    await Clipboard.setData(ClipboardData(text: prompt));
    if (!mounted) return;
    setState(() {
      _message = 'Prompt ကို Copy လုပ်ပြီးပါပြီ။ Gemini မှာ paste လုပ်ပါ။';
      _error = null;
    });
  }

  Future<void> _pasteReply() async {
    final reply = await showDialog<String>(context: context, builder: (_) => const _ReplyDialog());
    if (reply == null || reply.trim().isEmpty) return;
    final r = parseTeReply(reply, sourceMs: widget.project.videoDurationMs ?? 0, idSeed: DateTime.now().millisecondsSinceEpoch);
    if (!mounted) return;
    if (r.error != null) {
      setState(() {
        _error = r.error;
        _message = null;
      });
      return;
    }
    setState(() {
      _plan = _plan.copyWith(ops: [..._plan.ops, ...r.ops]);
      _error = null;
      _message = 'အကြံပြုချက် ${r.ops.length} ခု ထည့်ပြီး (စောင့်ဆိုင်း)။ ခွင့်ပြုမှသာ သုံးမယ်။'
          '${r.rejected.isEmpty ? '' : '\nချန်ထားတာ ${r.rejected.length} ခု: ${r.rejected.take(5).join('; ')}'}';
    });
  }

  Future<void> _findGaps() async {
    final ctrl = TextEditingController(text: '4');
    final secs = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('စာတန်းအကြား ရှာမယ်'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'အနည်းဆုံး ကြာချိန် (စက္ကန့်)', helperText: 'စာတန်း မပါတဲ့ ဒီထက်ရှည်တဲ့ နေရာတွေ'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('မလုပ်တော့ဘူး')),
          FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim())), child: const Text('ရှာမယ်')),
        ],
      ),
    );
    ctrl.dispose();
    if (secs == null || secs < 1) return;
    final studio = await _repo.getDoc(_projectId, DocKind.studioSrt);
    final src = (studio != null && studio.trim().isNotEmpty) ? studio : await _repo.getDoc(_projectId, DocKind.sourceSrt);
    final sourceMs = widget.project.videoDurationMs ?? 0;
    if (!mounted) return;
    if (src == null || src.trim().isEmpty || sourceMs <= 0) {
      setState(() {
        _error = 'စာတန်း (SRT) နဲ့ ဗီဒီယိုအရှည် လိုပါတယ်';
        _message = null;
      });
      return;
    }
    final gaps = findSubtitleGaps(parseSrt(src).entries, sourceMs: sourceMs, minGapMs: (secs * 1000).round());
    final props = gapProposals(gaps, idSeed: DateTime.now().millisecondsSinceEpoch);
    setState(() {
      _error = null;
      if (props.isEmpty) {
        _message = 'ဒီအတိုင်းအတာနဲ့ စာတန်းမပါတဲ့ နေရာ မတွေ့ပါ';
      } else {
        _plan = _plan.copyWith(ops: [..._plan.ops, ...props]);
        _message = 'Smart Cut အကြံပြုချက် ${props.length} ခု ထည့်ပြီး (စောင့်ဆိုင်း)။ စာတန်းမရှိတာကို ခန့်မှန်းတာသာ ဖြစ်လို့ ကိုယ်တိုင် စစ်ပြီး ခွင့်ပြုပါ။';
      }
    });
  }

  Future<void> _addOp() async {
    final op = await showDialog<TransformOp>(context: context, builder: (_) => const _OpDialog());
    if (op == null) return;
    setState(() => _plan = _plan.copyWith(ops: [..._plan.ops, op]));
  }

  void _toggle(TransformTool tool, bool enabled) {
    final next = {..._plan.enabledTools};
    if (enabled) {
      next.add(tool);
    } else {
      next.remove(tool);
    }
    setState(() => _plan = _plan.copyWith(enabledTools: next));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TE · Transformative Editor'),
        actions: [
          IconButton(
            tooltip: 'သိမ်းမယ်',
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(widget.project.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'မူရင်းဗီဒီယိုကို မပြင်ဘဲ ကိုယ်ပိုင်ရှင်းပြချက်၊ အမြင်နဲ့ Editing ပုံစံအသစ် ဖန်တီးရန်',
            style: TextStyle(color: DfColors.muted),
          ),
          if (_plan.fromNewerVersion)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DfColors.warn),
              ),
              child: const Text(
                'ဒီ Plan ကို app ဗားရှင်းအသစ်က ရေးထားတာ ဖြစ်တယ်။ ဒီ app မသိတဲ့ အချက်တွေကို မဖျက်ဘဲ ထိန်းထားမယ်။',
                style: TextStyle(fontSize: 13),
              ),
            ),
          const SizedBox(height: 14),
          _sectionTitle('လက်ရှိ Project အခြေအနေ'),
          _statRow('Video အပိုင်း', '${_timeline.pieces.length} ခု'),
          _statRow('Timeline အရှည်', '${(_timeline.videoMs / 60000).toStringAsFixed(1)} မိနစ်'),
          _statRow('Narration', '${_timeline.voices.length} ခု'),
          const SizedBox(height: 18),
          _sectionTitle('Editing Mode'),
          SegmentedButton<TransformMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: TransformMode.manual, label: Text('Manual')),
              ButtonSegment(value: TransformMode.aiAssisted, label: Text('AI Assisted')),
              ButtonSegment(value: TransformMode.hybrid, label: Text('Hybrid')),
            ],
            selected: {_plan.mode},
            onSelectionChanged: (value) => setState(() => _plan = _plan.copyWith(mode: value.first)),
          ),
          const SizedBox(height: 8),
          Text(
            switch (_plan.mode) {
              TransformMode.manual => 'ကိုယ်တိုင် Tool တွေရွေးပြီး ပြင်ဆင်မယ်။',
              TransformMode.aiAssisted => 'AI က Editing Plan အကြံပြုပေးမယ့် Mode ဖြစ်တယ်။ AI ချိတ်ဆက်မှုကို နောက်အဆင့်မှာ ထည့်မယ်။',
              TransformMode.hybrid => 'AI အကြံပြုချက်ကို ကိုယ်တိုင်စစ်ဆေး၊ ပြင်ဆင်ပြီးမှ အသုံးပြုမယ်။',
            },
            style: const TextStyle(color: DfColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          _sectionTitle('အသုံးပြုမယ့် Editing Tools'),
          const Text(
            'လိုအပ်တဲ့ Tool တွေကို ရွေးပါ။ ရွေးချယ်မှုတွေကို Project တစ်ခုချင်းစီအလိုက် သိမ်းထားမယ်။',
            style: TextStyle(color: DfColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (final tool in TransformTool.values)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _plan.enabledTools.contains(tool),
              onChanged: (value) => _toggle(tool, value ?? false),
              title: Text(tool.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${tool.description}\n${switch (tool.status) {
                  ToolStatus.rendered => 'Render မှာ ပါပြီ — ခွင့်ပြုထားတဲ့ လုပ်ဆောင်ချက်တွေ MP4 ထဲ ဝင်မယ် (ဖုန်းမစမ်းရသေး)',
                  ToolStatus.inStudio => 'Studio Editor မှာ အသုံးပြုလို့ရပြီ (TE ကနေ မချိတ်ရသေး)',
                  ToolStatus.planned => 'မဖြစ်သေး — မှတ်တမ်းသာ ထားနိုင်တယ်',
                }}',
                style: const TextStyle(fontSize: 12),
              ),
              isThreeLine: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          const SizedBox(height: 12),
          _sectionTitle('Edit လုပ်ဆောင်ချက် စာရင်း'),
          const Text(
            'AI အကြံပြုချက် (နောက်ပိုင်း) တွေက “စောင့်ဆိုင်း” အနေနဲ့သာ ဝင်လာမယ်။ ခွင့်ပြုမှသာ အသုံးပြုမယ်။ '
            'ခွင့်ပြုထားတဲ့ Smart Cut၊ Crop & Reframe၊ အလင်း/Contrast၊ Freeze Frame၊ Picture-in-Picture (ပုံ)၊ Motion Graphics (စာသား/မြား)၊ Sound Design (အသံ effect) တွေသာ Render မှာ ပါပါမယ်။ ကျန် tool တွေကို မှတ်တမ်းအဖြစ်သာ သိမ်းတယ်။',
            style: TextStyle(color: DfColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (_plan.ops.isEmpty)
            const Text('စာရင်း မရှိသေးပါ။', style: TextStyle(color: DfColors.muted)),
          for (final op in _plan.ops) _opTile(op),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addOp,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('လုပ်ဆောင်ချက် ထည့်မယ်'),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _findGaps,
              icon: const Icon(Icons.content_cut, size: 18),
              label: const Text('စာတန်းအကြား ဖြတ်ဖို့ ရှာမယ်'),
            ),
          ),
          const SizedBox(height: 12),
          _sectionTitle('Gemini အကြံပြုချက် (copy / paste)'),
          const Text(
            'API key မလိုပါ။ Prompt ကို Copy လုပ်ပြီး Gemini app မှာ paste၊ ပြန်ဖြေတာကို ဒီမှာ ထည့်ပါ။ '
            'အကြံပြုချက်တွေက “စောင့်ဆိုင်း” အဖြစ်သာ ဝင်မယ် — ကိုယ်တိုင် စစ်ပြီး ခွင့်ပြုမှသာ Render မှာ ပါမယ်။',
            style: TextStyle(color: DfColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(onPressed: _copyPrompt, icon: const Icon(Icons.copy, size: 18), label: const Text('Prompt Copy')),
              OutlinedButton.icon(onPressed: _pasteReply, icon: const Icon(Icons.paste, size: 18), label: const Text('Gemini ပြန်ဖြေ ထည့်မယ်')),
            ],
          ),
          const SizedBox(height: 12),
          _sectionTitle('ကိုယ်ပိုင် Editing ညွှန်ကြားချက်'),
          TextField(
            controller: _instructions,
            onChanged: (_) => setState(() {}),
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'ဥပမာ - အရေးကြီးတဲ့ Scene တွေကို Freeze Frame လုပ်ပြီး မြန်မာလို ရှင်းပြချက် ထည့်ပါ။',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_message != null)
            Text(_message!, style: const TextStyle(color: DfColors.ok)),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: DfColors.danger)),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'သိမ်းနေတယ်…' : 'TE Plan သိမ်းမယ်'),
          ),
          const SizedBox(height: 12),
          const Text(
            'မှတ်ချက် — Smart Cut၊ Crop & Reframe၊ Freeze Frame၊ Picture-in-Picture (ပုံ)၊ Motion Graphics နဲ့ Sound Design တို့ကို ခွင့်ပြုထားရင် Render မှာ ပါပါမယ် (ဖုန်းမှာ မစမ်းရသေးပါ)။ Split Screen၊ ဒုတိယဗီဒီယို PiP နဲ့ AI ကိုယ်တိုင်ချိတ်ဆက်တာတွေ မရှိသေးပါ။',
            style: TextStyle(color: DfColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  static String _t(int ms) {
    final sec = ms ~/ 1000;
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  }

  Widget _opTile(TransformOp op) {
    final (label, color) = switch (op.status) {
      OpStatus.proposed => ('စောင့်ဆိုင်း', DfColors.warn),
      OpStatus.approved => ('ခွင့်ပြုပြီး', DfColors.ok),
      OpStatus.rejected => ('ပယ်ထား', DfColors.muted),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DfColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DfColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${op.tool.title} · ${_t(op.startMs)}–${_t(op.endMs)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(label, style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
          if (op.source == OpSource.ai)
            const Text('AI အကြံပြုချက်', style: TextStyle(color: DfColors.muted, fontSize: 12)),
          if (op.note.isNotEmpty) Text(op.note, style: const TextStyle(fontSize: 13)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (op.status != OpStatus.approved)
                TextButton(
                  onPressed: () => setState(() => _plan = _plan.setOpStatus(op.id, OpStatus.approved)),
                  child: const Text('ခွင့်ပြု'),
                ),
              if (op.status != OpStatus.rejected)
                TextButton(
                  onPressed: () => setState(() => _plan = _plan.setOpStatus(op.id, OpStatus.rejected)),
                  child: const Text('ပယ်'),
                ),
              IconButton(
                tooltip: 'ဖျက်',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => setState(() => _plan = _plan.removeOp(op.id)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );

  Widget _statRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: DfColors.muted))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// A manual operation. The user creates it, so it starts approved.
class _OpDialog extends StatefulWidget {
  const _OpDialog();

  @override
  State<_OpDialog> createState() => _OpDialogState();
}

class _OpDialogState extends State<_OpDialog> {
  TransformTool _tool = TransformTool.freezeFrame;
  final _from = TextEditingController(text: '0');
  final _to = TextEditingController(text: '5');
  final _note = TextEditingController();
  double _zoom = 1.5;
  double _hold = 3.0;
  double _bright = 0.15;
  double _contrast = 0.0;
  String? _imgPath;
  double _isize = 0.25;
  AudioFile? _sound;
  double _svol = 0.8;
  String _kind = 'label';
  final _text = TextEditingController();
  double _mx = 0.5;
  double _my = 0.15;
  double _msize = 0.06;
  double _angle = 0;
  bool _bg = true;
  int _color = 0xFFFFEB3B;
  static const _colors = [0xFFFFFFFF, 0xFFFFEB3B, 0xFFFF5252, 0xFF69F0AE, 0xFF40C4FF];
  double _cx = 0.5;
  double _cy = 0.5;
  String? _err;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _note.dispose();
    _text.dispose();
    super.dispose();
  }

  bool get _point => _tool == TransformTool.freezeFrame || _tool == TransformTool.soundDesign;

  Future<void> _pickImage() async {
    try {
      final f = await AudioChannel.pickImage();
      if (f != null) setState(() => _imgPath = f);
    } catch (e) {
      setState(() => _err = 'ပုံ ရွေးမရပါ: $e');
    }
  }

  Future<void> _pickSound() async {
    try {
      final f = await AudioChannel.pickAudio();
      if (f != null) setState(() => _sound = f);
    } catch (e) {
      setState(() => _err = 'အသံဖိုင် ရွေးမရပါ: $e');
    }
  }

  Map<String, Object?> _params() {
    double r(double v) => double.parse(v.toStringAsFixed(2));
    switch (_tool) {
      case TransformTool.freezeFrame:
        return {'hold': double.parse(_hold.toStringAsFixed(1))};
      case TransformTool.pictureInPicture:
        final f = _imgPath;
        return f == null ? const {} : {'kind': 'image', 'path': f, 'x': r(_mx), 'y': r(_my), 'size': r(_isize), 'color': 0xFFFFFFFF};
      case TransformTool.soundDesign:
        final f = _sound;
        return f == null ? const {} : {'src': f.source, 'name': f.name, 'dur': f.durationMs, 'vol': r(_svol)};
      case TransformTool.colorGrade:
        return {'brightness': r(_bright), 'contrast': r(_contrast)};
      case TransformTool.cropReframe:
        return {'zoom': r(_zoom), 'cx': r(_cx), 'cy': r(_cy)};
      case TransformTool.motionGraphics:
        return {
          'kind': _kind,
          'x': r(_mx),
          'y': r(_my),
          'size': r(_msize),
          'color': _color,
          if (_kind == 'label') 'text': _text.text.trim(),
          if (_kind == 'label') 'bg': _bg,
          if (_kind == 'arrow') 'angle': _angle.roundToDouble(),
        };
      default:
        return const {};
    }
  }

  void _ok() {
    final a = double.tryParse(_from.text.trim());
    final b = _point ? a : double.tryParse(_to.text.trim());
    if (_tool == TransformTool.pictureInPicture && _imgPath == null) {
      setState(() => _err = 'ပုံ အရင်ရွေးပါ');
      return;
    }
    if (_tool == TransformTool.soundDesign && _sound == null) {
      setState(() => _err = 'အသံဖိုင် အရင်ရွေးပါ');
      return;
    }
    if (_tool == TransformTool.motionGraphics && _kind == 'label' && _text.text.trim().isEmpty) {
      setState(() => _err = 'Label စာသား ရေးပါ');
      return;
    }
    if (a == null || b == null || a < 0 || b < a) {
      setState(() => _err = 'စက္ကန့် မမှန်ပါ (စချိန် ≥ 0၊ ဆုံးချိန် ≥ စချိန်)');
      return;
    }
    Navigator.pop(
      context,
      TransformOp(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        tool: _tool,
        startMs: (a * 1000).round(),
        endMs: (b * 1000).round(),
        note: _note.text.trim(),
        params: _params(),
        status: OpStatus.approved,
      ),
    );
  }

  Widget _slider(String label, double v, double min, double max, void Function(double) set) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Slider(value: v, min: min, max: max, onChanged: (x) => setState(() => set(x))),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('လုပ်ဆောင်ချက် ထည့်မယ်'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<TransformTool>(
              initialValue: _tool,
              isExpanded: true,
              items: [for (final t in TransformTool.values) DropdownMenuItem(value: t, child: Text(t.title))],
              onChanged: (v) => setState(() => _tool = v ?? _tool),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _from,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: _tool == TransformTool.freezeFrame ? 'ရပ်မယ့် အချိန် (စက္ကန့်)' : (_tool == TransformTool.soundDesign ? 'အသံစမယ့် အချိန် (စက္ကန့်)' : 'စချိန် (စက္ကန့်)')),
                  ),
                ),
                if (!_point) const SizedBox(width: 8),
                if (!_point)
                Expanded(
                  child: TextField(
                    controller: _to,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'ဆုံးချိန် (စက္ကန့်)'),
                  ),
                ),
              ],
            ),
            if (_tool == TransformTool.colorGrade) ...[
              _slider('အလင်း ${(_bright * 100).round()}% (အနှုတ် = မှောင်)', _bright, -0.6, 0.6, (v) => _bright = v),
              _slider('Contrast ${(_contrast * 100).round()}%', _contrast, -0.6, 0.6, (v) => _contrast = v),
              const Text(
                'ဒါက ပုံသဏ္ဍာန်/mood ညှိဖို့ပါ (ဥပမာ ဇာတ်ရှိန်မြင့်တဲ့ နေရာကို မှောင်စေ၊ အလင်းဆွဲ)။ ပလက်ဖောင်း၏ မူပိုင်စစ်ဆေးမှုကို ရှောင်ဖို့ မဟုတ်ပါ၊ အဲဒီအတွက် မသုံးပါနဲ့။',
                style: TextStyle(color: DfColors.muted, fontSize: 12),
              ),
            ],
            if (_tool == TransformTool.pictureInPicture) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(_imgPath == null ? 'ပုံ ရွေးမယ်' : 'ပုံ ရွေးပြီး (ပြန်ရွေးလို့ရ)'),
              ),
              _slider('ဘယ်-ညာ ${(_mx * 100).round()}%', _mx, 0.0, 1.0, (v) => _mx = v),
              _slider('အပေါ်-အောက် ${(_my * 100).round()}%', _my, 0.0, 1.0, (v) => _my = v),
              _slider('အကျယ် ${(_isize * 100).round()}% (ဗီဒီယိုအကျယ်)', _isize, 0.05, 0.6, (v) => _isize = v),
              const Text(
                'ပုံတစ်ပုံကို ဗီဒီယိုပေါ် ထပ်ပြမယ်။ ဒုတိယဗီဒီယိုကို ထပ်တာ မရသေးပါ။ ကိုယ်ပိုင်/အသုံးပြုခွင့်ရှိတဲ့ ပုံသာ သုံးပါ။',
                style: TextStyle(color: DfColors.muted, fontSize: 12),
              ),
            ],
            if (_tool == TransformTool.soundDesign) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _pickSound,
                icon: const Icon(Icons.audiotrack, size: 18),
                label: Text(_sound == null ? 'အသံဖိုင် ရွေးမယ်' : '${_sound!.name} · ${(_sound!.durationMs / 1000).toStringAsFixed(1)}s'),
              ),
              _slider('အသံ ${(_svol * 100).round()}%', _svol, 0.05, 1.0, (v) => _svol = v),
              const Text(
                'ကိုယ့်ဖုန်းထဲက အသံဖိုင်ကို သုံးမယ် (မူရင်းဖိုင် မပြောင်း)။ အချိန်ကို မူရင်းဗီဒီယိုအပေါ် တိုင်းထားတယ်။ အသံက ဗီဒီယိုအဆုံး မကျော်ရပါ။ ကိုယ်ပိုင်/အသုံးပြုခွင့်ရှိတဲ့ အသံသာ သုံးပါ။',
                style: TextStyle(color: DfColors.muted, fontSize: 12),
              ),
            ],
            if (_tool == TransformTool.motionGraphics) ...[
              const SizedBox(height: 4),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'label', label: Text('စာသား')),
                  ButtonSegment(value: 'arrow', label: Text('မြား')),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() => _kind = v.first),
              ),
              if (_kind == 'label')
                TextField(
                  controller: _text,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Label စာသား'),
                ),
              _slider('ဘယ်-ညာ ${(_mx * 100).round()}%', _mx, 0.0, 1.0, (v) => _mx = v),
              _slider('အပေါ်-အောက် ${(_my * 100).round()}%', _my, 0.0, 1.0, (v) => _my = v),
              _slider('အရွယ်အစား ${(_msize * 100).round()}%', _msize, 0.03, 0.4, (v) => _msize = v),
              if (_kind == 'arrow') _slider('လှည့်ပုံ ${_angle.round()}° (0=ညာ၊ 90=အောက်)', _angle, 0, 359, (v) => _angle = v),
              if (_kind == 'label')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('နောက်ခံ အမည်း', style: TextStyle(fontSize: 14)),
                  value: _bg,
                  onChanged: (v) => setState(() => _bg = v),
                ),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in _colors)
                    GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(color: _color == c ? DfColors.accent : DfColors.line, width: _color == c ? 3 : 1),
                        ),
                      ),
                    ),
                ],
              ),
              const Text(
                'အချိန်ကို မူရင်းဗီဒီယိုအပေါ် တိုင်းထားတယ် — အပိုင်းဖြတ်၊ ရှေ့နောက်ရွှေ့ထားရင်လည်း အလိုက်သင့် လိုက်မယ်။',
                style: TextStyle(color: DfColors.muted, fontSize: 12),
              ),
            ],
            if (_tool == TransformTool.freezeFrame) ...[
              _slider('ရပ်မယ့် ကြာချိန် ${_hold.toStringAsFixed(1)} စက္ကန့်', _hold, 0.5, 15.0, (v) => _hold = v),
              const Text(
                'စချိန်ကနေ ပုံတစ်ပုံ ရပ်ပြမယ်။ ရပ်တဲ့အချိန်ကြောင့် နောက်ပိုင်း အချိန်တွေ နောက်ကျမယ် — Render screen မှာ edit အချိန်ကို ပြမယ်။',
                style: TextStyle(color: DfColors.muted, fontSize: 12),
              ),
            ],
            if (_tool == TransformTool.cropReframe) ...[
              _slider('Zoom ×${_zoom.toStringAsFixed(2)}', _zoom, 1.0, 3.0, (v) => _zoom = v),
              _slider('ဘယ်-ညာ ${(_cx * 100).round()}%', _cx, 0.0, 1.0, (v) => _cx = v),
              _slider('အပေါ်-အောက် ${(_cy * 100).round()}%', _cy, 0.0, 1.0, (v) => _cy = v),
              const Text(
                'အစွန်းတွေမှာ အလွတ်မပေါ်အောင် နေရာကို အလိုအလျောက် ညှိမယ်။',
                style: TextStyle(color: DfColors.muted, fontSize: 12),
              ),
            ],
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'မှတ်ချက်')),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(color: DfColors.danger))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('မလုပ်တော့ဘူး')),
        FilledButton(onPressed: _ok, child: const Text('ထည့်မယ်')),
      ],
    );
  }
}

class _ReplyDialog extends StatefulWidget {
  const _ReplyDialog();

  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<_ReplyDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gemini ပြန်ဖြေချက်'),
      content: TextField(
        controller: _c,
        minLines: 6,
        maxLines: 12,
        decoration: const InputDecoration(hintText: 'ဒီမှာ paste လုပ်ပါ', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final d = await Clipboard.getData('text/plain');
            if (d?.text != null) setState(() => _c.text = d!.text!);
          },
          child: const Text('Paste'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('မလုပ်တော့ဘူး')),
        FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('စစ်ပြီး ထည့်မယ်')),
      ],
    );
  }
}
