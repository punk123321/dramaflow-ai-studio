import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/segments.dart';
import '../core/theme.dart';
import '../data/project.dart';
import '../platform/video_import.dart';
import '../state/project_store.dart';

/// Step 1 of the workflow: pick the original video, split it into segments,
/// and keep the index. The original video file is only read, never changed.
class VideoIndexPanel extends StatefulWidget {
  const VideoIndexPanel({super.key, required this.project});

  final Project project;

  @override
  State<VideoIndexPanel> createState() => _VideoIndexPanelState();
}

class _VideoIndexPanelState extends State<VideoIndexPanel> {
  List<SegmentSpec> _specs = [];
  bool _loading = true;
  bool _picking = false;
  String? _error;

  /// Minutes per segment. 0 means "custom".
  int _preset = 10;
  final _custom = TextEditingController(text: '12');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VideoIndexPanel old) {
    super.didUpdateWidget(old);
    if (old.project.id != widget.project.id) _load();
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = context.read<ProjectStore>();
    setState(() => _loading = true);
    try {
      final list = await store.segmentsOf(widget.project);
      if (!mounted) return;
      setState(() {
        _specs = sortedSegments(list);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Index ကို ဖတ်မရပါဘူး။ App ကို ပိတ်ပြီး ပြန်ဖွင့်ကြည့်ပါ။';
      });
    }
  }

  Future<bool> _confirm(String text) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('မလုပ်တော့ဘူး')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ဆက်လုပ်မယ်')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _pick() async {
    final store = context.read<ProjectStore>();
    final p = widget.project;
    if (_specs.isNotEmpty) {
      final ok = await _confirm('Video အသစ် ရွေးရင် လက်ရှိ index ပျက်သွားမယ်။ ဆက်လုပ်မလား။');
      if (!ok || !mounted) return;
    }
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final v = await VideoImport.pick();
      if (v != null) {
        await store.attachVideo(p, v);
        if (mounted) setState(() => _specs = []);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = 'ဒီ video ကို ဖတ်မရပါဘူး။ MP4 ဖိုင်နဲ့ ထပ်စမ်းပါ။ (${e.message ?? e.code})');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Video ရွေးလို့ မရပါဘူး။ ထပ်စမ်းကြည့်ပါ။');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save(List<SegmentSpec> specs) async {
    final store = context.read<ProjectStore>();
    final sorted = sortedSegments(specs);
    final ok = await store.saveSegments(widget.project, sorted);
    if (!mounted) return;
    setState(() {
      if (ok) {
        _specs = sorted;
        _error = null;
      } else {
        _error = store.error;
      }
    });
  }

  Future<void> _generate() async {
    final minutes = _preset == 0 ? int.tryParse(_custom.text.trim()) : _preset;
    if (minutes == null || minutes < 1) {
      setState(() => _error = 'စိတ်ကြိုက် မိနစ်ကို 1 နဲ့ အထက် ဂဏန်း ထည့်ပါ။');
      return;
    }
    if (_specs.isNotEmpty) {
      final ok = await _confirm('လက်ရှိ segment များကို ဖျက်ပြီး အသစ်ခွဲမယ်။ ကိုယ်တိုင်ပြင်ထားတာတွေ ပျက်သွားမယ်။');
      if (!ok || !mounted) return;
    }
    final dur = widget.project.videoDurationMs ?? 0;
    await _save(buildSegments(dur, minutes * 60000));
  }

  Future<void> _edit(int? index) async {
    final dur = widget.project.videoDurationMs ?? 0;
    final start = index != null ? _specs[index].startMs : (_specs.isEmpty ? 0 : _specs.last.endMs);
    final end = index != null ? _specs[index].endMs : dur;
    final result = await showDialog<SegmentSpec>(
      context: context,
      builder: (_) => _SegmentDialog(startMs: start, endMs: end, durationMs: dur, isNew: index == null),
    );
    if (result == null || !mounted) return;
    final next = [..._specs];
    if (index == null) {
      next.add(result);
    } else {
      next[index] = result;
    }
    await _save(next);
  }

  Future<void> _remove(int index) async {
    final next = [..._specs]..removeAt(index);
    await _save(next);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!p.hasVideo) ...[
          const Text(
            'မူရင်း video ကို ရွေးပါ။ ဖိုင်ကို မကူးဘူး၊ မပြင်ဘူး၊ ဘယ်နေရာကရလဲ ဆိုတာပဲ မှတ်ထားပါတယ်။',
            style: TextStyle(color: DfColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
        ] else
          _VideoCard(project: p),
        FilledButton.icon(
          onPressed: _picking ? null : _pick,
          icon: _picking
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.video_file_outlined),
          label: Text(p.hasVideo ? 'တခြား video ရွေးမယ်' : 'Video ရွေးမယ်'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: DfColors.danger, fontSize: 13)),
        ],
        if (p.hasVideo) ...[
          const SizedBox(height: 14),
          const Divider(color: DfColors.line, height: 1),
          const SizedBox(height: 12),
          const Text('Segment တစ်ခု ကြာချိန်', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final m in const [5, 10, 15, 20])
                ChoiceChip(
                  label: Text('$m မိနစ်'),
                  selected: _preset == m,
                  onSelected: (_) => setState(() => _preset = m),
                ),
              ChoiceChip(
                label: const Text('စိတ်ကြိုက်'),
                selected: _preset == 0,
                onSelected: (_) => setState(() => _preset = 0),
              ),
            ],
          ),
          if (_preset == 0) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _custom,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'မိနစ်', isDense: true),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: _generate, child: const Text('Segment ခွဲမယ်')),
          const SizedBox(height: 14),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else ...[
            Text(
              _specs.isEmpty ? 'Segment မရှိသေးပါဘူး။' : 'Segment ${_specs.length} ခု',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (hasOverlap(_specs))
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Segment တချို့ အချိန်ထပ်နေပါတယ်။ ရည်ရွယ်ချက်ရှိရင် ဆက်သုံးလို့ရပါတယ်။',
                  style: TextStyle(color: DfColors.warn, fontSize: 13),
                ),
              ),
            const SizedBox(height: 6),
            for (var i = 0; i < _specs.length; i++) _SegmentRow(
              number: i + 1,
              spec: _specs[i],
              onEdit: () => _edit(i),
              onDelete: () => _remove(i),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text('Segment ထည့်မယ်'),
            ),
            if (_specs.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'ပြင်တိုင်း အလိုအလျောက် သိမ်းပါတယ်။ App ပိတ်ပြီး ပြန်ဖွင့်ရင်လည်း ကျန်ပါတယ်။',
                  style: TextStyle(color: DfColors.muted, fontSize: 12),
                ),
              ),
          ],
        ],
      ],
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final thumb = project.videoThumb;
    final w = project.videoWidth ?? 0;
    final h = project.videoHeight ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DfColors.raise,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 112,
              height: 64,
              child: thumb == null
                  ? const ColoredBox(color: DfColors.line, child: Icon(Icons.movie_outlined))
                  : Image.file(
                      File(thumb),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: DfColors.line, child: Icon(Icons.movie_outlined)),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(project.videoName ?? 'video', maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${formatTime(project.videoDurationMs ?? 0)} · ${w > 0 ? '$w×$h' : '-'} · ${formatSize(project.videoSize ?? 0)}',
                  style: const TextStyle(color: DfColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.number,
    required this.spec,
    required this.onEdit,
    required this.onDelete,
  });

  final int number;
  final SegmentSpec spec;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(color: DfColors.raise, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('#$number', style: const TextStyle(color: DfColors.muted, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              '${formatTime(spec.startMs)} – ${formatTime(spec.endMs)}  (${formatTime(spec.lengthMs)})',
              style: const TextStyle(fontSize: 14),
            ),
          ),
          IconButton(
            tooltip: 'ပြင်မယ်',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'ဖျက်မယ်',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }
}

class _SegmentDialog extends StatefulWidget {
  const _SegmentDialog({
    required this.startMs,
    required this.endMs,
    required this.durationMs,
    required this.isNew,
  });

  final int startMs;
  final int endMs;
  final int durationMs;
  final bool isNew;

  @override
  State<_SegmentDialog> createState() => _SegmentDialogState();
}

class _SegmentDialogState extends State<_SegmentDialog> {
  late final TextEditingController _start = TextEditingController(text: formatTime(widget.startMs));
  late final TextEditingController _end = TextEditingController(text: formatTime(widget.endMs));
  String? _error;

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _submit() {
    final s = parseTime(_start.text);
    final e = parseTime(_end.text);
    if (s == null || e == null) {
      setState(() => _error = 'အချိန်ကို 1:30 ဒါမှမဟုတ် 1:02:03 ပုံစံနဲ့ ထည့်ပါ။');
      return;
    }
    final err = validateSegment(startMs: s, endMs: e, durationMs: widget.durationMs);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, SegmentSpec(s, e));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isNew ? 'Segment ထည့်မယ်' : 'Segment ပြင်မယ်'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _start,
            keyboardType: TextInputType.datetime,
            decoration: const InputDecoration(labelText: 'စတင်ချိန် (ဥပမာ 0:00)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _end,
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(labelText: 'ဆုံးချိန် (video ${formatTime(widget.durationMs)})'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: DfColors.danger, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('မလုပ်တော့ဘူး')),
        FilledButton(onPressed: _submit, child: const Text('သိမ်းမယ်')),
      ],
    );
  }
}
