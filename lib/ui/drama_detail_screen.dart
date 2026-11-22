import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/drama.dart';
import '../state/library_store.dart';
import 'drama_sheet.dart';
import 'widgets.dart';

class DramaDetailScreen extends StatelessWidget {
  const DramaDetailScreen({super.key, required this.dramaId});

  final int dramaId;

  Future<void> _delete(BuildContext context, LibraryStore store, Drama d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ဇာတ်လမ်း ဖျက်မလား'),
        content: Text(
          '“${d.displayTitle}” နဲ့ အပိုင်းစာရင်းကို ဖျက်မယ်။ Project တွေနဲ့ video ဖိုင်တွေကိုတော့ မဖျက်ပါဘူး။',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('မဖျက်ဘူး')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ဖျက်မယ်')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.of(context).pop();
    await store.deleteDrama(d);
  }

  Future<void> _addEpisode(BuildContext context, LibraryStore store, Drama d) async {
    final eps = store.episodesOf(d.id!);
    final next = eps.isEmpty ? 1 : eps.map((e) => e.number).reduce((a, b) => a > b ? a : b) + 1;
    final input = await showDialog<_EpisodeInput>(
      context: context,
      builder: (_) => _EpisodeDialog(initialNumber: next),
    );
    if (input == null || !context.mounted) return;
    final err = await store.addEpisode(
      d.id!,
      number: input.number,
      durationMin: input.durationMin,
      source: input.source,
    );
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final d = store.byId(dramaId);
    if (d == null) {
      return DfScaffold(
        appBar: AppBar(),
        body: const Center(child: Text('ဒီဇာတ်လမ်း မရှိတော့ပါဘူး။')),
      );
    }
    final eps = store.episodesOf(dramaId);
    final done = eps.where((e) => e.completed).length;
    final showZh = d.titleMy.isNotEmpty && d.titleZh.isNotEmpty;

    return DfScaffold(
      appBar: AppBar(
        title: Text(d.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'ပြင်မယ်',
            onPressed: () => showDramaSheet(context, existing: d),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'ဖျက်မယ်',
            onPressed: () => _delete(context, store, d),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addEpisode(context, store, d),
        icon: const Icon(Icons.add),
        label: const Text('အပိုင်းထည့်'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          if (store.error != null) ErrorBanner(store.error!),
          Row(
            children: [
              Poster(title: d.displayTitle, width: 56, height: 76),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showZh) Text(d.titleZh, style: const TextStyle(color: DfColors.muted)),
                    Text('Season ${d.season}'),
                    Text(
                      'ပြီးပြီ $done / ${eps.length} ပိုင်း',
                      style: const TextStyle(color: DfColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (d.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(d.description, style: const TextStyle(color: DfColors.muted)),
          ],
          const SectionTitle('အပိုင်းများ'),
          if (eps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'အပိုင်း မရှိသေးပါဘူး။ “အပိုင်းထည့်” ကို နှိပ်ပါ။',
                style: TextStyle(color: DfColors.muted),
              ),
            ),
          for (final e in eps) _EpisodeTile(episode: e),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode});

  final Episode episode;

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final parts = <String>[
      if (episode.durationMin > 0) '${episode.durationMin} မိနစ်',
      if (episode.source.isNotEmpty) episode.source,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        gradient: DfGradients.glass,
        color: DfColors.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DfColors.glassEdge),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('အပိုင်း ${episode.number}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (parts.isNotEmpty)
                    Text(
                      parts.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: DfColors.muted, fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
          Switch(
            value: episode.completed,
            onChanged: (v) => store.setEpisodeCompleted(episode, v),
          ),
          IconButton(
            tooltip: 'ဖျက်မယ်',
            onPressed: () => store.deleteEpisode(episode),
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }
}

class _EpisodeInput {
  const _EpisodeInput(this.number, this.durationMin, this.source);

  final int number;
  final int durationMin;
  final String source;
}

class _EpisodeDialog extends StatefulWidget {
  const _EpisodeDialog({required this.initialNumber});

  final int initialNumber;

  @override
  State<_EpisodeDialog> createState() => _EpisodeDialogState();
}

class _EpisodeDialogState extends State<_EpisodeDialog> {
  late final TextEditingController _number = TextEditingController(text: '${widget.initialNumber}');
  final _duration = TextEditingController();
  final _source = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _duration.dispose();
    _source.dispose();
    super.dispose();
  }

  void _submit() {
    final n = int.tryParse(_number.text.trim());
    final dText = _duration.text.trim();
    final dur = dText.isEmpty ? 0 : int.tryParse(dText);
    if (n == null || n < 1) {
      setState(() => _error = 'အပိုင်းနံပါတ်ကို 1 နဲ့ အထက် ဂဏန်း ထည့်ပါ။');
      return;
    }
    if (dur == null || dur < 0) {
      setState(() => _error = 'ကြာချိန်ကို မိနစ် ဂဏန်းနဲ့ ထည့်ပါ။');
      return;
    }
    Navigator.pop(context, _EpisodeInput(n, dur, _source.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('အပိုင်းထည့်မယ်'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _number,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'အပိုင်း နံပါတ်'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _duration,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'ကြာချိန် (မိနစ်၊ မရှိလည်းရ)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _source,
              decoration: const InputDecoration(labelText: 'ရင်းမြစ် (ဥပမာ YouTube၊ ဖိုင်)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: DfColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('မလုပ်တော့ဘူး')),
        FilledButton(onPressed: _submit, child: const Text('ထည့်မယ်')),
      ],
    );
  }
}
