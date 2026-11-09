import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/drama.dart';
import '../state/library_store.dart';

/// Bottom sheet to add a drama, or edit one when [existing] is given.
Future<void> showDramaSheet(BuildContext context, {Drama? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DramaSheet(existing: existing),
  );
}

class _DramaSheet extends StatefulWidget {
  const _DramaSheet({this.existing});

  final Drama? existing;

  @override
  State<_DramaSheet> createState() => _DramaSheetState();
}

class _DramaSheetState extends State<_DramaSheet> {
  late final TextEditingController _zh = TextEditingController(text: widget.existing?.titleZh ?? '');
  late final TextEditingController _my = TextEditingController(text: widget.existing?.titleMy ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _season = TextEditingController(text: '${widget.existing?.season ?? 1}');
  String? _error;

  @override
  void dispose() {
    _zh.dispose();
    _my.dispose();
    _desc.dispose();
    _season.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final zh = _zh.text.trim();
    final my = _my.text.trim();
    final season = int.tryParse(_season.text.trim());
    if (zh.isEmpty && my.isEmpty) {
      setState(() => _error = 'တရုတ်နာမည် ဒါမှမဟုတ် မြန်မာနာမည် တစ်ခုတော့ ထည့်ပါ။');
      return;
    }
    if (season == null || season < 1) {
      setState(() => _error = 'Season ကို 1 နဲ့ အထက် ဂဏန်း ထည့်ပါ။');
      return;
    }
    final store = context.read<LibraryStore>();
    final nav = Navigator.of(context);
    final desc = _desc.text.trim();
    final existing = widget.existing;
    if (existing == null) {
      await store.addDrama(titleZh: zh, titleMy: my, description: desc, season: season);
    } else {
      await store.updateDrama(existing, titleZh: zh, titleMy: my, description: desc, season: season);
    }
    if (nav.mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'ဇာတ်လမ်းအသစ်' : 'ဇာတ်လမ်း ပြင်မယ်',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _zh,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'တရုတ်နာမည် (Chinese title)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _my,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'မြန်မာနာမည်'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _season,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Season'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'အကျဉ်းချုပ် (မရှိလည်းရ)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _submit, child: const Text('သိမ်းမယ်')),
          ],
        ),
      ),
    );
  }
}
