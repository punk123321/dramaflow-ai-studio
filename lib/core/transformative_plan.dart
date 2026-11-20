import 'dart:convert';

/// Transformative Editor plan. Pure Dart, no Flutter.
///
/// The plan is stored per project (documents, kind `transformative_plan`).
/// It is a DESCRIPTION of intended edits. Nothing here changes the original
/// video, and an operation is never executed unless the user approved it.
///
/// Versions
/// - 1: mode, tool toggles, free-text instructions.
/// - 2: adds [ops] (reviewable edit operations).
/// A file written by a NEWER app keeps its version and every field this app
/// does not understand, so opening and saving it here does not destroy data.

const transformPlanVersion = 2;

/// Editing approach selected for one project.
enum TransformMode { manual, aiAssisted, hybrid }

enum TransformTool {
  smartCut,
  cropReframe,
  pictureInPicture,
  commentaryVoiceOver,
  freezeFrame,
  sceneReordering,
  motionGraphics,
  soundDesign,
  splitScreen,
  criticalCommentary,
  colorGrade,
  speedChange,
  blur,
  mirrorFlip,
}

/// How far a tool really goes today. Used so the screen never suggests more
/// than the code does.
enum ToolStatus {
  /// Not built. The plan can only record the wish.
  planned,

  /// Works in the Studio Editor (Stage 4), not through TE yet.
  inStudio,

  /// Approved operations of this tool are applied when a video is rendered.
  rendered,

  /// Applied at render time, but written without a phone to test on. It may
  /// not look right yet.
  experimental,
}

extension TransformToolLabel on TransformTool {
  String get title => switch (this) {
        TransformTool.smartCut => 'Smart Cut',
        TransformTool.cropReframe => 'Crop & Reframe',
        TransformTool.pictureInPicture => 'Picture-in-Picture',
        TransformTool.commentaryVoiceOver => 'Commentary / Voice-over',
        TransformTool.freezeFrame => 'Freeze Frame',
        TransformTool.sceneReordering => 'Scene Reordering',
        TransformTool.motionGraphics => 'Motion Graphics',
        TransformTool.soundDesign => 'Sound Design',
        TransformTool.splitScreen => 'Split Screen',
        TransformTool.criticalCommentary => 'Critical Commentary / Recap',
        TransformTool.colorGrade => 'Brightness & Contrast',
        TransformTool.speedChange => 'Speed',
        TransformTool.blur => 'Blur',
        TransformTool.mirrorFlip => 'Mirror / Flip',
      };

  String get description => switch (this) {
        TransformTool.smartCut => 'မလိုအပ်တဲ့ အချိန်ပိုင်းတွေကို ဖြတ်ထုတ်ရန် (စာတန်းအကြား ရှာပေးနိုင်တယ်)',
        TransformTool.cropReframe => 'ပုံရိပ်ကို Crop၊ Zoom နဲ့ Reframe ပြုလုပ်ရန်',
        TransformTool.pictureInPicture => 'ပုံ (picture) ကို အပေါ်ထပ်ပြရန် — ဒုတိယဗီဒီယို ထပ်တာ မရသေးပါ',
        TransformTool.commentaryVoiceOver => 'ကိုယ်ပိုင်ရှင်းပြချက်နဲ့ Voice-over ထည့်ရန်',
        TransformTool.freezeFrame => 'အရေးကြီးတဲ့ Scene ကို ရပ်ပြပြီး ရှင်းပြရန်',
        TransformTool.sceneReordering => 'Scene အစီအစဉ်ကို ပြန်စီရန်',
        TransformTool.motionGraphics => 'စာသား၊ မြား၊ Label၊ အကွက်/ဝိုင်း၊ အလင်းထိုး (spot)၊ ဘောင် (frame) ထည့်ရန်',
        TransformTool.soundDesign => 'အသံအကျိုးသက်ရောက်မှုနဲ့ Background Audio ချိန်ရန်',
        TransformTool.splitScreen => 'မျက်နှာပြင်ကို နှစ်ပိုင်းခွဲပြီး မူရင်းဗီဒီယိုရဲ့ အချိန်နှစ်ခု တစ်ပြိုင်နက်ပြရန် (စမ်းသပ်ဆဲ)',
        TransformTool.criticalCommentary => 'ဇာတ်လမ်းကို ကိုယ်ပိုင်ဝေဖန်ချက်နဲ့ အသစ်ပြန်တင်ပြရန်',
        TransformTool.speedChange => 'အချိန်ပိုင်းတစ်ခုကို အမြန်/နှေးပြီး ပြရန် (၀.၂၅× မှ ၄×၊ အသံနှုန်း မပြောင်း) — စမ်းသပ်ဆဲ',
        TransformTool.blur => 'အချိန်ပိုင်းတစ်ခုလုံးကို Gaussian Blur နဲ့ မှုန်ဝါးစေရန် (strength ၀.၅–၅၀) — စမ်းသပ်ဆဲ',
        TransformTool.mirrorFlip => 'အချိန်ပိုင်းတစ်ခုကို ဘယ်-ညာ သို့မဟုတ် အပေါ်-အောက် လှန်ပြရန် (ဖွဲ့စည်းမှု/ဖန်တီးမှုအတွက်) — စမ်းသပ်ဆဲ',
        TransformTool.colorGrade => 'အလင်း/အမှောင်၊ ကွဲလွဲမှု (contrast) ကို အချိန်ပိုင်းအလိုက် ညှိရန် (ပုံသဏ္ဍာန်/mood အတွက်)',
      };

  /// What the app really does for each tool today (see CHECKLIST.md).
  ToolStatus get status => switch (this) {
        TransformTool.splitScreen ||
        TransformTool.speedChange ||
        TransformTool.blur ||
        TransformTool.mirrorFlip =>
          ToolStatus.experimental,
        TransformTool.colorGrade ||
        TransformTool.smartCut ||
        TransformTool.pictureInPicture ||
        TransformTool.cropReframe ||
        TransformTool.freezeFrame ||
        TransformTool.motionGraphics ||
        TransformTool.soundDesign =>
          ToolStatus.rendered,
        TransformTool.commentaryVoiceOver ||
        TransformTool.sceneReordering ||
        TransformTool.criticalCommentary =>
          ToolStatus.inStudio,
      };
}

enum OpStatus { proposed, approved, rejected }

enum OpSource { manual, ai }

/// One reviewable edit step, for example "freeze the frame at 01:20".
class TransformOp {
  const TransformOp({
    required this.id,
    required this.tool,
    required this.startMs,
    required this.endMs,
    this.note = '',
    this.params = const {},
    this.status = OpStatus.proposed,
    this.source = OpSource.manual,
    this.extra = const {},
  });

  /// A suggestion that waits for the user. AI suggestions must be made this
  /// way: they never start approved.
  factory TransformOp.proposal({
    required String id,
    required TransformTool tool,
    required int startMs,
    required int endMs,
    String note = '',
    Map<String, Object?> params = const {},
    OpSource source = OpSource.ai,
  }) =>
      TransformOp(
        id: id,
        tool: tool,
        startMs: startMs,
        endMs: endMs,
        note: note,
        params: params,
        source: source,
      );

  final String id;
  final TransformTool tool;

  /// Range on the ORIGINAL video.
  final int startMs;
  final int endMs;
  final String note;
  final Map<String, Object?> params;
  final OpStatus status;
  final OpSource source;

  /// Fields this app does not know, kept so saving does not drop them.
  final Map<String, Object?> extra;

  bool get valid => startMs >= 0 && endMs >= startMs;

  /// Only approved operations may ever be executed.
  bool get runnable => status == OpStatus.approved && valid;

  TransformOp withStatus(OpStatus s) => TransformOp(
        id: id,
        tool: tool,
        startMs: startMs,
        endMs: endMs,
        note: note,
        params: params,
        status: s,
        source: source,
        extra: extra,
      );

  /// Same operation with some fields changed. Unknown fields are kept.
  TransformOp copyWith({
    int? startMs,
    int? endMs,
    String? note,
    Map<String, Object?>? params,
    OpStatus? status,
  }) =>
      TransformOp(
        id: id,
        tool: tool,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        note: note ?? this.note,
        params: params ?? this.params,
        status: status ?? this.status,
        source: source,
        extra: extra,
      );

  Map<String, Object?> toJson() => {
        ...extra,
        'id': id,
        'tool': tool.name,
        's': startMs,
        'e': endMs,
        if (note.isNotEmpty) 'note': note,
        if (params.isNotEmpty) 'params': params,
        'status': status.name,
        'src': source.name,
      };

  /// Null when the map cannot be understood (the caller keeps it as is).
  static TransformOp? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final tool = _byName(TransformTool.values, raw['tool']);
    final s = raw['s'];
    final e = raw['e'];
    if (id is! String || id.isEmpty || tool == null || s is! int || e is! int) return null;
    final p = raw['params'];
    return TransformOp(
      id: id,
      tool: tool,
      startMs: s,
      endMs: e,
      note: raw['note'] is String ? raw['note'] as String : '',
      params: p is Map ? {for (final x in p.entries) x.key.toString(): x.value} : const {},
      // An unknown or missing status is the safe one: not approved.
      status: _byName(OpStatus.values, raw['status']) ?? OpStatus.proposed,
      source: _byName(OpSource.values, raw['src']) ?? OpSource.manual,
      extra: {
        for (final e in raw.entries)
          if (!_opKnown.contains(e.key)) e.key.toString(): e.value,
      },
    );
  }
}

const _opKnown = {'id', 'tool', 's', 'e', 'note', 'params', 'status', 'src'};

T? _byName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

class TransformativePlan {
  const TransformativePlan({
    this.version = transformPlanVersion,
    this.mode = TransformMode.hybrid,
    this.enabledTools = const {},
    this.instructions = '',
    this.ops = const [],
    this.unknownTools = const [],
    this.unknownOps = const [],
    this.extra = const {},
  });

  /// Version of the file this plan was read from (or the current one).
  final int version;
  final TransformMode mode;
  final Set<TransformTool> enabledTools;
  final String instructions;
  final List<TransformOp> ops;

  /// Kept from a newer file so saving does not drop them.
  final List<String> unknownTools;
  final List<Object?> unknownOps;
  final Map<String, Object?> extra;

  /// The file came from a newer app than this one.
  bool get fromNewerVersion => version > transformPlanVersion;

  List<TransformOp> get approvedOps => [for (final o in ops) if (o.runnable) o];
  List<TransformOp> get pendingOps => [for (final o in ops) if (o.status == OpStatus.proposed) o];

  TransformativePlan copyWith({
    TransformMode? mode,
    Set<TransformTool>? enabledTools,
    String? instructions,
    List<TransformOp>? ops,
  }) =>
      TransformativePlan(
        version: version,
        mode: mode ?? this.mode,
        enabledTools: enabledTools ?? this.enabledTools,
        instructions: instructions ?? this.instructions,
        ops: ops ?? this.ops,
        unknownTools: unknownTools,
        unknownOps: unknownOps,
        extra: extra,
      );

  TransformativePlan setOpStatus(String id, OpStatus status) =>
      copyWith(ops: [for (final o in ops) o.id == id ? o.withStatus(status) : o]);

  /// Replaces the operation with the same id (used after the user edits it).
  TransformativePlan replaceOp(TransformOp op) =>
      copyWith(ops: [for (final o in ops) o.id == op.id ? op : o]);

  TransformativePlan removeOp(String id) => copyWith(ops: [for (final o in ops) if (o.id != id) o]);

  Map<String, Object?> toJson() => {
        // Unknown fields first, so the fields we know always win.
        ...extra,
        // Never write a version lower than the one that was read.
        'version': version > transformPlanVersion ? version : transformPlanVersion,
        'mode': mode.name,
        'tools': [
          ...(enabledTools.map((t) => t.name).toList()..sort()),
          ...unknownTools,
        ],
        'instructions': instructions,
        'ops': [for (final o in ops) o.toJson(), ...unknownOps],
      };

  String encode() => jsonEncode(toJson());

  static const _known = {'version', 'mode', 'tools', 'instructions', 'ops'};

  static TransformativePlan decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const TransformativePlan();
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return const TransformativePlan();

      final v = json['version'];
      final version = v is int && v >= 1 ? v : 1;

      final tools = <TransformTool>{};
      final unknownTools = <String>[];
      final rawTools = json['tools'];
      if (rawTools is List) {
        for (final value in rawTools) {
          if (value is! String) continue;
          final t = _byName(TransformTool.values, value);
          if (t != null) {
            tools.add(t);
          } else {
            unknownTools.add(value);
          }
        }
      }

      final ops = <TransformOp>[];
      final unknownOps = <Object?>[];
      final rawOps = json['ops'];
      if (rawOps is List) {
        for (final o in rawOps) {
          final op = TransformOp.fromJson(o);
          if (op != null) {
            ops.add(op);
          } else {
            unknownOps.add(o);
          }
        }
      }

      return TransformativePlan(
        version: version,
        mode: _byName(TransformMode.values, json['mode']) ?? TransformMode.hybrid,
        enabledTools: tools,
        instructions: json['instructions'] is String ? json['instructions'] as String : '',
        ops: ops,
        unknownTools: unknownTools,
        unknownOps: unknownOps,
        extra: {
          for (final e in json.entries)
            if (!_known.contains(e.key)) e.key.toString(): e.value,
        },
      );
    } catch (_) {
      return const TransformativePlan();
    }
  }
}
