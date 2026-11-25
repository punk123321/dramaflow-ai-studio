import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/orphan_renders.dart';
import '../core/render_plan.dart' show safeFileName;
import '../core/stage.dart';
import '../core/theme.dart';
import '../data/export_item.dart';
import '../data/project.dart';
import '../platform/audio_channel.dart';
import '../platform/part_saver.dart' show galleryFailText;
import '../platform/render_channel.dart';
import '../state/project_store.dart';
import '../state/render_store.dart';
import 'description_card.dart';
import 'render_panel.dart' show showVideoPreview;

/// Stage 6: put a finished video in the phone's gallery or a folder, and keep
/// the export history.
class SavePanel extends StatefulWidget {
  const SavePanel({super.key, required this.project});

  final Project project;

  @override
  State<SavePanel> createState() => _SavePanelState();
}

class _SavePanelState extends State<SavePanel> {
  final _repo = ExportRepo();
  List<ExportItem> _items = [];
  bool _loading = true;
  String? _msg;
  bool _error = false;
  int? _busyId;
  List<RenderFile> _orphans = [];
  List<RenderFile> _unfinished = [];
  String? _busyPath;

  int get _pid => widget.project.id!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _items = await _repo.forProject(_pid);
      try {
        final files = await RenderChannel.listRenders();
        final prefix = '${safeFileName(widget.project.name)}_';
        _orphans = orphanRenders(files, {for (final i in _items) i.path}, prefix: prefix);
        _unfinished = unfinishedRenders(files, prefix: prefix);
      } catch (_) {}
    } catch (e) {
      _say('ဖတ်လို့မရပါ: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _say(String m, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _msg = m;
      _error = error;
    });
  }

  Future<void> _markDone() async {
    final store = context.read<ProjectStore>();
    final p = store.current;
    if (p != null && !p.isDone(Stage.save)) await store.setStageDone(p, Stage.save, true);
  }

  Future<void> _gallery(ExportItem e) async {
    setState(() => _busyId = e.id);
    try {
      await RenderChannel.saveToGallery(e.path, e.name);
      if (e.id != null) await _repo.markInGallery(e.id!);
      _say('Gallery (Movies/DramaFlow) ထဲ သိမ်းပြီး');
      await _markDone();
      await _load();
    } catch (err) {
      final text = '$err';
      _say(text.contains('use_export') ? 'ဒီ Android ဗားရှင်းမှာ "ဖိုင်အဖြစ်သိမ်း" ကို သုံးပါ။' : 'Gallery ထဲ သိမ်းလို့မရပါ: $err', error: true);
    }
    if (mounted) setState(() => _busyId = null);
  }

  Future<void> _orphanGallery(RenderFile f) async {
    setState(() => _busyPath = f.path);
    try {
      await RenderChannel.saveToGallery(f.path, f.name);
      _say('${f.name} ကို Gallery (Movies/DramaFlow) ထဲ သိမ်းပြီး');
      await _markDone();
    } catch (err) {
      _say('Gallery ထဲ သိမ်းလို့မရပါ: ${galleryFailText('$err')}', error: true);
    }
    if (mounted) setState(() => _busyPath = null);
  }

  Future<void> _orphanDelete(RenderFile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ဒီဖိုင်ကို ဖျက်မလား?'),
        content: const Text('App ထဲက ဖိုင်ကို ဖျက်မယ်။ Gallery ထဲ မသိမ်းရသေးရင် ပြန်မရတော့ပါဘူး။'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('မဖျက်ဘူး')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ဖျက်မယ်')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await RenderChannel.deleteRender(f.path);
      await _load();
    } catch (err) {
      _say('ဖျက်လို့မရပါ: $err', error: true);
    }
  }

  Future<void> _asFile(ExportItem e) async {
    try {
      final ok = await AudioChannel.export(e.path, '${e.name}.mp4', 'video/mp4');
      if (ok == true) {
        _say('ဖိုင်သိမ်းပြီး');
        await _markDone();
      }
    } catch (err) {
      _say('သိမ်းလို့မရပါ: $err', error: true);
    }
  }

  Future<void> _delete(ExportItem e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ဒီဗီဒီယိုကို ဖျက်မလား?'),
        content: const Text('App ထဲက ဖိုင်ကို ဖျက်မယ်။ Gallery ထဲ သိမ်းပြီးသားကို မထိပါဘူး။'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('မဖျက်ဘူး')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ဖျက်မယ်')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await RenderChannel.deleteRender(e.path);
      if (e.id != null) await _repo.delete(e.id!);
      await _load();
    } catch (err) {
      _say('ဖျက်လို့မရပါ: $err', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Refresh when a render finishes while this panel is open.
    context.watch<RenderStore>();
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_msg != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (_error ? DfColors.danger : DfColors.ok).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_msg!, style: const TextStyle(fontSize: 13)),
          ),
        Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _load, child: const Text('စာရင်း ပြန်ယူ'))),
        DescriptionCard(project: widget.project),
        if (_items.isEmpty)
          const Text('ထုတ်ပြီးသား ဗီဒီယို မရှိသေးပါ။ အဆင့် ၅ မှာ အရင်ထုတ်ပါ။', style: TextStyle(color: DfColors.muted, fontSize: 13)),
        for (final e in _items)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                Text(
                  '${e.height}p · ${(e.durationMs ~/ 60000).toString().padLeft(2, '0')}:${((e.durationMs ~/ 1000) % 60).toString().padLeft(2, '0')} · '
                  '${(e.sizeBytes / 1048576).toStringAsFixed(1)} MB${e.inGallery ? ' · Gallery ထဲရှိ' : ''}',
                  style: const TextStyle(color: DfColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 2, children: [
                  TextButton(onPressed: () => showVideoPreview(context, e.path), child: const Text('ကြည့်')),
                  TextButton(onPressed: _busyId == e.id ? null : () => _gallery(e), child: const Text('Gallery ထဲသိမ်း')),
                  TextButton(onPressed: () => _asFile(e), child: const Text('ဖိုင်အဖြစ်သိမ်း')),
                  TextButton(onPressed: () => _delete(e), child: const Text('ဖျက်')),
                ]),
              ]),
            ),
          ),
        if (_orphans.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('App ထဲမှာ တွေ့တဲ့ ဗီဒီယို (မှတ်တမ်းထဲ မပါ)', style: TextStyle(fontWeight: FontWeight.w600, color: DfColors.accent)),
          const Text('ထုတ်ပြီးတာကို screen ဆီ မပို့လိုက်နိုင်တဲ့ ဖိုင်တွေ ဖြစ်နိုင်တယ်။ ဒီကနေ သိမ်းလို့ရတယ်။', style: TextStyle(color: DfColors.muted, fontSize: 12)),
          const SizedBox(height: 6),
          for (final f in _orphans)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  Text(
                    '${(f.sizeBytes / 1048576).toStringAsFixed(1)} MB · ${DateTime.fromMillisecondsSinceEpoch(f.modifiedMs).toString().substring(0, 16)}',
                    style: const TextStyle(color: DfColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 2, children: [
                    TextButton(onPressed: () => showVideoPreview(context, f.path), child: const Text('ကြည့်')),
                    TextButton(onPressed: _busyPath == f.path ? null : () => _orphanGallery(f), child: const Text('Gallery ထဲသိမ်း')),
                    TextButton(onPressed: () => _orphanDelete(f), child: const Text('ဖျက်')),
                  ]),
                ]),
              ),
            ),
        ],
        if (_unfinished.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'မပြီးသေးတဲ့ ဖိုင် ${_unfinished.length} ခု ရှိတယ် (${(_unfinished.fold<int>(0, (a, f) => a + f.sizeBytes) / 1048576).toStringAsFixed(0)} MB)။ '
              'Render က အဆုံးမရောက်ဘဲ ရပ်သွားတာမို့ ဖွင့်လို့မရဘူး၊ နောက် export စတဲ့အခါ အလိုအလျောက် ဖျက်မယ်။',
              style: const TextStyle(color: DfColors.warn, fontSize: 12.5),
            ),
          ),
      ],
    );
  }
}
