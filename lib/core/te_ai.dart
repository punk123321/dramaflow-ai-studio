import 'dart:convert';

import 'te_compile.dart';
import 'transformative_plan.dart';

/// Gemini handoff for the Transformative Editor. Pure Dart, no network.
///
/// The app writes a prompt, the user pastes it into Gemini, and pastes the
/// reply back. Every suggestion in the reply is checked and added as
/// PROPOSED. Nothing is applied until the user approves it, and no AI key is
/// needed.

/// Tools the render really supports (see te_compile.dart).
const aiTools = [
  TransformTool.cropReframe,
  TransformTool.freezeFrame,
  TransformTool.motionGraphics,
];

const maxAiOps = 30;
const maxPromptSubtitleChars = 20000;

String buildTePrompt({
  required String projectName,
  required int sourceMs,
  required String subtitles,
  String instructions = '',
  Set<TransformTool> tools = const {},
}) {
  final use = [for (final t in aiTools) if (tools.isEmpty || tools.contains(t)) t];
  final cut = subtitles.length > maxPromptSubtitleChars;
  final subs = cut ? subtitles.substring(0, maxPromptSubtitleChars) : subtitles;
  final b = StringBuffer()
    ..writeln('You are helping me edit a recap video about "$projectName".')
    ..writeln('The original video is ${(sourceMs / 1000).round()} seconds long.')
    ..writeln('Suggest a SMALL number of editing steps (at most 12) that make my recap more '
        'explanatory and original: emphasise key moments, point things out, add short labels.')
    ..writeln('Use only these tools:');
  if (use.contains(TransformTool.cropReframe)) {
    b.writeln('- cropReframe: {"tool":"cropReframe","from":SEC,"to":SEC,"zoom":1.0-3.0,"cx":0-1,"cy":0-1,"note":"why"}');
  }
  if (use.contains(TransformTool.freezeFrame)) {
    b.writeln('- freezeFrame: {"tool":"freezeFrame","at":SEC,"hold":0.5-15,"note":"why"}');
  }
  if (use.contains(TransformTool.motionGraphics)) {
    b
      ..writeln('- motionGraphics label: {"tool":"motionGraphics","kind":"label","from":SEC,"to":SEC,"text":"short text in Burmese","x":0-1,"y":0-1,"note":"why"}')
      ..writeln('- motionGraphics arrow: {"tool":"motionGraphics","kind":"arrow","from":SEC,"to":SEC,"x":0-1,"y":0-1,"angle":0-359,"note":"why"}');
  }
  b
    ..writeln('All times are SECONDS in the ORIGINAL video, between 0 and ${(sourceMs / 1000).round()}. x and y are 0-1 from the top-left.')
    ..writeln('Do not suggest anything that hides, removes or covers a watermark or logo, and do not suggest ways to avoid copyright checks.');
  if (instructions.trim().isNotEmpty) {
    b.writeln('My own instructions: ${instructions.trim()}');
  }
  b
    ..writeln('Reply with ONE JSON code block and nothing else, in this form:')
    ..writeln('```json')
    ..writeln('{"ops":[ ... ]}')
    ..writeln('```')
    ..writeln('')
    ..writeln('Subtitles of the video${cut ? ' (shortened)' : ''}:')
    ..writeln(subs);
  return b.toString();
}

class AiParseResult {
  const AiParseResult(this.ops, this.rejected, {this.error});

  /// Valid suggestions, always `proposed` and from the AI.
  final List<TransformOp> ops;

  /// Why each unusable suggestion was left out (Burmese, for the user).
  final List<String> rejected;

  /// The whole reply could not be read.
  final String? error;
}

String? _json(String reply) {
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(reply);
  if (fence != null) return fence.group(1)!.trim();
  // No code fence: take from the first { or [ to the matching last } or ].
  final o = reply.indexOf('{');
  final l = reply.indexOf('[');
  final isList = l >= 0 && (o < 0 || l < o);
  final a = isList ? l : o;
  final z = reply.lastIndexOf(isList ? ']' : '}');
  return a >= 0 && z > a ? reply.substring(a, z + 1) : null;
}

int? _ms(Object? sec) => sec is num && sec.isFinite && sec >= 0 ? (sec * 1000).round() : null;

/// Reads a Gemini reply. Never throws. [idSeed] makes the new ids unique.
AiParseResult parseTeReply(String reply, {required int sourceMs, required int idSeed}) {
  final raw = _json(reply);
  if (raw == null) return const AiParseResult([], [], error: 'JSON ရှာမတွေ့ပါ။ Gemini ကို code block တစ်ခုနဲ့ ပြန်ခိုင်းပါ');
  Object? data;
  try {
    data = jsonDecode(raw);
  } catch (_) {
    return const AiParseResult([], [], error: 'JSON ဖတ်လို့မရပါ (ပုံစံမှားနေတယ်)');
  }
  final list = data is Map ? data['ops'] : (data is List ? data : null);
  if (list is! List) return const AiParseResult([], [], error: '"ops" စာရင်း မတွေ့ပါ');

  final ops = <TransformOp>[];
  final rejected = <String>[];
  var n = 0;
  for (final item in list) {
    n++;
    if (ops.length >= maxAiOps) {
      rejected.add('$maxAiOps ခုထက် ပိုတာတွေကို ချန်ထားတယ်');
      break;
    }
    if (item is! Map) {
      rejected.add('#$n — object မဟုတ်ပါ');
      continue;
    }
    final op = _one(item, n, sourceMs, idSeed);
    if (op.$1 != null) {
      ops.add(op.$1!);
    } else {
      rejected.add('#$n — ${op.$2}');
    }
  }
  return AiParseResult(ops, rejected);
}

(TransformOp?, String) _one(Map item, int n, int sourceMs, int idSeed) {
  final tool = TransformTool.values.where((t) => t.name == item['tool']).firstOrNull;
  if (tool == null || !aiTools.contains(tool)) return (null, 'tool "${item['tool']}" ကို မထောက်ပံ့ပါ');

  final note = item['note'] is String ? (item['note'] as String).trim() : '';
  final id = 'ai-$idSeed-$n';
  bool inside(int ms) => ms >= 0 && (sourceMs <= 0 || ms <= sourceMs);

  int s;
  int e;
  Map<String, Object?> params;
  if (tool == TransformTool.freezeFrame) {
    final at = _ms(item['at']);
    if (at == null || !inside(at)) return (null, 'အချိန် မမှန်ပါ');
    final hold = item['hold'];
    params = {'hold': hold is num ? hold.toDouble() : 3.0};
    if (freezeHoldMs(params) == null) return (null, 'ရပ်ကြာချိန် မမှန်ပါ (၀.၅–၃၀ စက္ကန့်)');
    s = at;
    e = at;
  } else {
    final from = _ms(item['from']);
    final to = _ms(item['to']);
    if (from == null || to == null || to < from || !inside(from) || !inside(to)) {
      return (null, 'အချိန်ပိုင်း မမှန်ပါ');
    }
    s = from;
    e = to;
    if (tool == TransformTool.cropReframe) {
      final z = item['zoom'];
      final cx = item['cx'];
      final cy = item['cy'];
      params = {
        'zoom': z is num ? z.toDouble() : -1.0,
        'cx': cx is num ? cx.toDouble() : 0.5,
        'cy': cy is num ? cy.toDouble() : 0.5,
      };
      if (cropFromParams(params) == null) return (null, 'zoom/နေရာ တန်ဖိုး မမှန်ပါ');
    } else {
      final kind = item['kind'] == 'arrow' ? 'arrow' : (item['kind'] == 'label' ? 'label' : null);
      if (kind == null) return (null, 'kind က label သို့ arrow ဖြစ်ရမယ်');
      double num_(Object? v, double d) => v is num ? v.toDouble() : d;
      params = {
        'kind': kind,
        'x': num_(item['x'], 0.5),
        'y': num_(item['y'], kind == 'label' ? 0.15 : 0.5),
        'size': num_(item['size'], kind == 'label' ? 0.06 : 0.2),
        'color': 0xFFFFEB3B,
        if (kind == 'label') 'text': item['text'] is String ? (item['text'] as String).trim() : '',
        if (kind == 'arrow') 'angle': num_(item['angle'], 0),
      };
      if (motionFromParams(params) == null) return (null, 'label စာသား/နေရာ/အရွယ် မမှန်ပါ');
    }
  }
  return (
    TransformOp.proposal(id: id, tool: tool, startMs: s, endMs: e, note: note, params: params),
    '',
  );
}
