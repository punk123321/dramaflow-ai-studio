import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/timeline.dart';
import '../core/transformative_plan.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';

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
            'ခွင့်ပြုထားတဲ့ Crop & Reframe နဲ့ Freeze Frame တွေသာ Render မှာ ပါပါမယ်။ ကျန် tool တွေကို မှတ်တမ်းအဖြစ်သာ သိမ်းတယ်။',
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
            'မှတ်ချက် — ဒီအဆင့်မှာ TE Plan ကို Project ထဲ သိမ်းဆည်းနိုင်ပါပြီ။ AI Scene Analysis၊ PIP၊ Freeze Frame၊ Split Screen နဲ့ Motion Graphics တို့ရဲ့ Render လုပ်ဆောင်ချက်တွေကို နောက်အဆင့်တွေမှာ တစ်ခုချင်း ချိတ်ဆက်မယ်။',
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
  double _cx = 0.5;
  double _cy = 0.5;
  String? _err;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _note.dispose();
    super.dispose();
  }

  void _ok() {
    final a = double.tryParse(_from.text.trim());
    final freeze = _tool == TransformTool.freezeFrame;
    final b = freeze ? a : double.tryParse(_to.text.trim());
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
        params: _tool == TransformTool.freezeFrame
            ? {'hold': double.parse(_hold.toStringAsFixed(1))}
            : _tool == TransformTool.cropReframe
            ? {
                'zoom': double.parse(_zoom.toStringAsFixed(2)),
                'cx': double.parse(_cx.toStringAsFixed(2)),
                'cy': double.parse(_cy.toStringAsFixed(2)),
              }
            : const {},
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
                    decoration: InputDecoration(labelText: _tool == TransformTool.freezeFrame ? 'ရပ်မယ့် အချိန် (စက္ကန့်)' : 'စချိန် (စက္ကန့်)'),
                  ),
                ),
                if (_tool != TransformTool.freezeFrame) const SizedBox(width: 8),
                if (_tool != TransformTool.freezeFrame)
                Expanded(
                  child: TextField(
                    controller: _to,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'ဆုံးချိန် (စက္ကန့်)'),
                  ),
                ),
              ],
            ),
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
