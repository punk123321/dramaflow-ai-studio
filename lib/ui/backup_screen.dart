import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/backup.dart';
import '../core/theme.dart';
import '../data/backup_repo.dart';
import '../platform/handoff_channel.dart';
import '../state/project_store.dart';
import 'widgets.dart';

/// Backup and restore of all projects as one JSON file the user keeps.
/// Videos, audio and pictures are not inside it.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _repo = BackupRepo();
  bool _busy = false;
  String? _msg;
  bool _err = false;

  void _say(String m, {bool error = false}) => setState(() {
        _msg = m;
        _err = error;
      });

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final all = await _repo.readAll();
      if (all.isEmpty) {
        _say('Backup လုပ်စရာ project မရှိသေးပါ။', error: true);
      } else {
        final now = DateTime.now();
        final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
        final ok = await HandoffChannel.saveTextFile('dramaflow_backup_$stamp.json', encodeBackup(all, nowMs: now.millisecondsSinceEpoch));
        if (ok == true) {
          _say('Project ${all.length} ခု သိမ်းပြီးပါပြီ။ ဖိုင်ကို Google Drive စတာတွေမှာ ထပ်ကူးထားပါ။');
        } else {
          _say('မသိမ်းဘဲ ပယ်ထားပါတယ်။');
        }
      }
    } catch (e) {
      _say('Backup မရပါ: $e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final f = await HandoffChannel.pickTextFile();
      if (f == null) {
        _say('မရွေးဘဲ ပယ်ထားပါတယ်။');
      } else {
        final r = parseBackup(f.text);
        if (r.error != null) {
          _say(r.error!, error: true);
        } else if (mounted) {
          final yes = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('ပြန်ယူမလား'),
              content: Text(
                'Project ${r.projects.length} ခု ထည့်မယ်။ ရှိပြီးသား project တွေကို မထိပါဘူး၊ အသစ်အနေနဲ့ ထပ်တိုးမှာပါ။'
                '${r.skipped > 0 ? '\n(ပျက်နေလို့ ${r.skipped} ခု ချန်ထားတယ်)' : ''}'
                '\n\nဗီဒီယို၊ အသံဖိုင်၊ ပုံတွေ မပါပါဘူး။ ဗီဒီယိုက ဖွင့်မရရင် Stage 1 မှာ ပြန်ရွေးပါ။',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('မလုပ်တော့ဘူး')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ပြန်ယူမယ်')),
              ],
            ),
          );
          if (yes == true) {
            final n = await _repo.restore(r.projects);
            if (mounted) await context.read<ProjectStore>().load();
            _say('Project $n ခု ပြန်ထည့်ပြီးပါပြီ။');
          } else {
            _say('မပြန်ယူဘဲ ပယ်ထားပါတယ်။');
          }
        }
      }
    } catch (e) {
      _say('ပြန်ယူလို့ မရပါ: $e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return DfScaffold(
      appBar: AppBar(title: const Text('Backup / Restore')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
          'Project အားလုံးရဲ့ မှတ်ချက်၊ စာတန်း၊ edit၊ TE plan၊ video index ကို ဖိုင်တစ်ခုအဖြစ် သိမ်းမယ်။ '
          'ဗီဒီယို၊ အသံဖိုင်၊ ပုံ၊ ထုတ်ပြီး MP4 တွေ မပါပါဘူး။ ဒါတွေက ဖုန်းထဲမှာပဲ ရှိနေမယ်။',
          style: TextStyle(color: DfColors.muted, fontSize: 13),
        ),
        const SectionTitle('Backup'),
        FilledButton.icon(onPressed: _busy ? null : _backup, icon: const Icon(Icons.save_alt, size: 18), label: const Text('Backup ဖိုင် သိမ်းမယ်')),
        const SectionTitle('Restore'),
        OutlinedButton.icon(onPressed: _busy ? null : _restore, icon: const Icon(Icons.restore, size: 18), label: const Text('Backup ဖိုင်ကနေ ပြန်ယူမယ်')),
        if (_msg != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(_msg!, style: TextStyle(color: _err ? DfColors.danger : DfColors.ok, fontSize: 13)),
          ),
      ]),
    );
  }
}
