import 'package:flutter/material.dart';

import '../core/timeline.dart';
import '../core/transformative_plan.dart';
import '../core/theme.dart';
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
        _message = 'TE Plan ကို သိမ်းပြီးပါပြီ။';
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'သိမ်းမရပါ: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
              subtitle: Text(tool.description, style: const TextStyle(fontSize: 12)),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          const SizedBox(height: 12),
          _sectionTitle('ကိုယ်ပိုင် Editing ညွှန်ကြားချက်'),
          TextField(
            controller: _instructions,
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
