import 'dart:io';

import 'package:flutter/material.dart';

import '../core/assembly.dart';
import '../core/srt.dart';
import '../core/theme.dart';
import '../data/assembly_settings_repo.dart';
import '../data/project.dart';
import '../platform/assembly_client.dart';

/// Makes an SRT from the sound of the project's video with AssemblyAI. Returns
/// the SRT text when it is ready and the user taps "ထည့်မယ်", otherwise null.
/// The video is only read; only its sound is sent.
Future<String?> showAsrDialog(BuildContext context, Project project) {
  return showDialog<String>(context: context, barrierDismissible: false, builder: (_) => _AsrDialog(project: project));
}

class _AsrDialog extends StatefulWidget {
  const _AsrDialog({required this.project});

  final Project project;

  @override
  State<_AsrDialog> createState() => _AsrDialogState();
}

class _AsrDialogState extends State<_AsrDialog> {
  final _repo = AssemblySettingsRepo();
  final _lang = TextEditingController();
  AssemblySettings _s = const AssemblySettings();
  bool _loaded = false;
  bool _running = false;
  String _stage = '';
  String? _error;
  String? _srt;
  int _count = 0;
  AssemblyClient? _client;

  @override
  void initState() {
    super.initState();
    _repo.load().then((s) {
      if (!mounted) return;
      setState(() {
        _s = s;
        _lang.text = s.language;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _client?.cancel();
    _lang.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final uri = widget.project.sourceVideoUri;
    if (uri == null) return;
    final lang = _lang.text.trim();
    setState(() {
      _running = true;
      _error = null;
      _srt = null;
      _stage = 'အသံကို ဗီဒီယိုထဲကနေ ထုတ်နေတယ် …';
    });
    final client = AssemblyClient(_s.apiKey.trim());
    _client = client;
    File? tmp;
    try {
      final audio = await AssemblyClient.extractAudio(uri);
      tmp = File(audio.path);
      if (audio.wholeFile && mounted) setState(() => _stage = 'အသံကို သီးသန့်မဖြတ်နိုင်လို့ ဗီဒီယိုတစ်ခုလုံး တင်မယ် …');
      final text = await client.transcribe(tmp, lang, (s) {
        if (mounted) setState(() => _stage = s);
      });
      final parsed = parseSrt(text);
      if (parsed.entries.isEmpty) throw const FormatException('အသံထဲက စာ မတွေ့ပါ (ဘာသာစကား code မှန်လား စစ်ပါ)');
      await _repo.save(_s.copyWith(language: lang));
      if (mounted) {
        setState(() {
          _srt = serializeSrt(parsed.entries);
          _count = parsed.entries.length;
        });
      }
    } on AsrCanceled {
      // The user stopped it.
    } on HttpException catch (e) {
      if (mounted && !client.canceled) setState(() => _error = e.message);
    } catch (e) {
      // Stopping closes the connection, which throws too; that is not an error to show.
      if (mounted && !client.canceled) setState(() => _error = '$e');
    } finally {
      try {
        await tmp?.delete();
      } catch (_) {}
      _client = null;
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    return AlertDialog(
      title: const Text('အသံကနေ SRT ထုတ်'),
      content: SingleChildScrollView(
        child: !_loaded
            ? const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.sourceVideoUri == null)
                    const Text('ဒီ project မှာ ဗီဒီယို မရွေးရသေးပါ။', style: TextStyle(color: DfColors.warn))
                  else if (!_s.hasKey)
                    const Text('AssemblyAI key မထည့်ရသေးပါ။ Settings › AssemblyAI မှာ ထည့်ပါ။', style: TextStyle(color: DfColors.warn))
                  else ...[
                    TextField(
                      controller: _lang,
                      enabled: !_running && _srt == null,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'ဘာသာစကား code (zh၊ en၊ my၊ ဗလာ = အလိုအလျောက်)'),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'ဗီဒီယိုထဲက အသံကိုပဲ AssemblyAI ဆီ ပို့ပါတယ်။ ဗီဒီယိုမူရင်းကို မပြင်ပါဘူး။ ဖိုင်ကြီးရင် အချိန်ကြာပြီး data သုံးပါတယ်။ Credit ကုန်နိုင်ပါတယ်။',
                      style: TextStyle(color: DfColors.muted, fontSize: 12),
                    ),
                  ],
                  if (_running) ...[
                    const SizedBox(height: 14),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    Text(_stage, style: const TextStyle(fontSize: 13)),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: DfColors.danger, fontSize: 13)),
                  ],
                  if (_srt != null) ...[
                    const SizedBox(height: 12),
                    Text('ပြီးပြီ — စာကြောင်း $_count ခု ရတယ်။ အမှားတွေ ပါနိုင်လို့ Studio ထဲမှာ ပြန်စစ်ပါ။', style: const TextStyle(color: DfColors.ok, fontSize: 13)),
                  ],
                ],
              ),
      ),
      actions: [
        if (_running)
          TextButton(onPressed: () => _client?.cancel(), child: const Text('ရပ်မယ်'))
        else ...[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ပိတ်')),
          if (_srt != null)
            FilledButton(onPressed: () => Navigator.pop(context, _srt), child: const Text('ထည့်မယ်'))
          else if (_loaded && _s.hasKey && p.sourceVideoUri != null)
            FilledButton(onPressed: _start, child: const Text('စမယ်')),
        ],
      ],
    );
  }
}
