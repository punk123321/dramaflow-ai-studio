import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/project_store.dart';

/// Bottom sheet that creates a project. Returns when the sheet closes.
Future<void> showNewProjectSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _NewProjectSheet(),
  );
}

class _NewProjectSheet extends StatefulWidget {
  const _NewProjectSheet();

  @override
  State<_NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends State<_NewProjectSheet> {
  final _name = TextEditingController();
  final _drama = TextEditingController();
  final _episode = TextEditingController(text: '1');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _drama.dispose();
    _episode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final drama = _drama.text.trim();
    final ep = int.tryParse(_episode.text.trim());
    if (name.isEmpty || drama.isEmpty) {
      setState(() => _error = 'Project နာမည်နဲ့ ဇာတ်လမ်းနာမည် နှစ်ခုလုံး ထည့်ပါ။');
      return;
    }
    if (ep == null || ep < 1) {
      setState(() => _error = 'အပိုင်းနံပါတ်ကို 1 နဲ့ အထက် ဂဏန်း ထည့်ပါ။');
      return;
    }
    final store = context.read<ProjectStore>();
    final nav = Navigator.of(context);
    await store.create(name: name, dramaTitle: drama, episode: ep);
    if (nav.mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Project အသစ်', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Project နာမည်'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _drama,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'ဇာတ်လမ်း နာမည်'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _episode,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'အပိုင်း နံပါတ်'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _submit, child: const Text('ဖန်တီးမယ်')),
          ],
        ),
      ),
    );
  }
}

/// Asks for one line of text. Returns null when cancelled.
Future<String?> askText(BuildContext context, String title, String initial) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextDialog(title: title, initial: initial),
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(controller: _c, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('မလုပ်တော့ဘူး')),
        FilledButton(
          onPressed: () {
            final v = _c.text.trim();
            Navigator.pop(context, v.isEmpty ? null : v);
          },
          child: const Text('သိမ်းမယ်'),
        ),
      ],
    );
  }
}

Future<bool> confirmDelete(BuildContext context, String name) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Project ဖျက်မလား'),
      content: Text(
        '“$name” ကို ဖျက်မယ်။ ဖုန်းထဲက မူရင်း video ဖိုင်ကိုတော့ မဖျက်ပါဘူး။',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('မဖျက်ဘူး')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ဖျက်မယ်')),
      ],
    ),
  );
  return ok ?? false;
}
