import 'package:flutter/material.dart';

import '../core/gemini_tts.dart';
import '../core/theme.dart';
import '../data/ai_settings_repo.dart';
import 'backup_screen.dart';
import 'widgets.dart';

/// App-wide settings: the optional Gemini key, backup, and a short "about".
/// Only things that really exist are shown (no language/theme switches yet).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _repo = AiSettingsRepo();
  final _keyC = TextEditingController();
  final _modelC = TextEditingController();
  GeminiTtsSettings _ai = const GeminiTtsSettings();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyC.dispose();
    _modelC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await _repo.load();
    if (!mounted) return;
    setState(() {
      _ai = s;
      _keyC.text = s.apiKey;
      _modelC.text = s.model;
      _loaded = true;
    });
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save({bool clearKey = false}) async {
    final model = _modelC.text.trim().isEmpty ? defaultTtsModel : _modelC.text.trim();
    final next = _ai.copyWith(apiKey: clearKey ? '' : _keyC.text.trim(), model: model);
    await _repo.save(next);
    if (!mounted) return;
    if (clearKey) _keyC.clear();
    setState(() => _ai = next);
    _say(clearKey ? 'Key ကို ဖျက်ပြီးပါပြီ။' : 'သိမ်းပြီးပါပြီ။');
  }

  @override
  Widget build(BuildContext context) {
    return DfScaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                const SectionTitle('AI Providers'),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome_rounded, color: DfColors.accent),
                          const SizedBox(width: 10),
                          const Expanded(child: Text('Gemini API (လိုချင်မှ သုံးမယ်)', style: TextStyle(fontWeight: FontWeight.w600))),
                          Text(
                            _ai.ready ? '✓ ထည့်ထား' : 'မထည့်ရသေး',
                            style: TextStyle(color: _ai.ready ? DfColors.ok : DfColors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'မထည့်လည်း ရပါတယ်။ ဖုန်း TTS၊ Mic၊ Gemini app ထဲ copy/paste နဲ့ အရင်အတိုင်း သုံးလို့ရပါတယ်။',
                        style: TextStyle(color: DfColors.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _keyC,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(labelText: 'API key (Google AI Studio က ယူ)'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _modelC,
                        autocorrect: false,
                        decoration: const InputDecoration(labelText: 'Model နာမည်'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: FilledButton(onPressed: () => _save(), child: const Text('သိမ်းမယ်'))),
                          if (_ai.apiKey.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            OutlinedButton(onPressed: () => _save(clearKey: true), child: const Text('Key ဖျက်')),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Key ကို ဒီဖုန်းထဲ app ရဲ့ သီးသန့်နေရာမှာ စာသားအတိုင်း သိမ်းတယ် (Backup ထဲ မပါ)။ '
                        'Gemini API သုံးတဲ့အခါ စာသားကို Google ဆီ ပို့ပါတယ်။ Billing မဖွင့်ရင် 403 ပြနိုင်ပါတယ်။',
                        style: TextStyle(color: DfColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Data'),
                _Card(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.backup_rounded, color: DfColors.accent),
                    title: const Text('Backup / Restore'),
                    subtitle: const Text('Project တွေ သိမ်း/ပြန်ယူ', style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BackupScreen())),
                  ),
                ),
                const SectionTitle('About'),
                const _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DramaFlow AI Studio', style: TextStyle(fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text(
                        'Project၊ script၊ အသံ အားလုံး ဒီဖုန်းထဲမှာပဲ သိမ်းတယ်။ မူရင်းဗီဒီယိုဖိုင်ကို ဘယ်တော့မှ မပြင်ပါဘူး။',
                        style: TextStyle(color: DfColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: DfGradients.glass,
        color: DfColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DfColors.glassEdge),
      ),
      child: child,
    );
  }
}
