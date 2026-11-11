import 'dart:convert';

/// Editing approach selected for one Transformative Editor project.
enum TransformMode { manual, aiAssisted, hybrid }

/// Transformative tools are an additional edit plan, not replacements for the
/// existing Studio Editor timeline or renderer.
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
      };

  String get description => switch (this) {
        TransformTool.smartCut => 'မလိုအပ်တဲ့ အချိန်ပိုင်းတွေကို ရွေးချယ်ဖြတ်တောက်ရန်',
        TransformTool.cropReframe => 'ပုံရိပ်ကို Crop၊ Zoom နဲ့ Reframe ပြုလုပ်ရန်',
        TransformTool.pictureInPicture => 'ဒုတိယဗီဒီယို သို့မဟုတ် ပုံကို အပေါ်ထပ်ပြရန်',
        TransformTool.commentaryVoiceOver => 'ကိုယ်ပိုင်ရှင်းပြချက်နဲ့ Voice-over ထည့်ရန်',
        TransformTool.freezeFrame => 'အရေးကြီးတဲ့ Scene ကို ရပ်ပြပြီး ရှင်းပြရန်',
        TransformTool.sceneReordering => 'Scene အစီအစဉ်ကို ပြန်စီရန်',
        TransformTool.motionGraphics => 'စာသား၊ မြား၊ Label နဲ့ Infographic ထည့်ရန်',
        TransformTool.soundDesign => 'အသံအကျိုးသက်ရောက်မှုနဲ့ Background Audio ချိန်ရန်',
        TransformTool.splitScreen => 'မျက်နှာပြင်ကို နှစ်ပိုင်း သို့မဟုတ် အများပိုင်းခွဲရန်',
        TransformTool.criticalCommentary => 'ဇာတ်လမ်းကို ကိုယ်ပိုင်ဝေဖန်ချက်နဲ့ အသစ်ပြန်တင်ပြရန်',
      };
}

/// Versioned TE settings stored independently per project.
class TransformativePlan {
  const TransformativePlan({
    this.version = 1,
    this.mode = TransformMode.hybrid,
    this.enabledTools = const {},
    this.instructions = '',
  });

  final int version;
  final TransformMode mode;
  final Set<TransformTool> enabledTools;
  final String instructions;

  TransformativePlan copyWith({
    TransformMode? mode,
    Set<TransformTool>? enabledTools,
    String? instructions,
  }) =>
      TransformativePlan(
        version: version,
        mode: mode ?? this.mode,
        enabledTools: enabledTools ?? this.enabledTools,
        instructions: instructions ?? this.instructions,
      );

  Map<String, Object?> toJson() => {
        'version': 1,
        'mode': mode.name,
        'tools': enabledTools.map((tool) => tool.name).toList()..sort(),
        'instructions': instructions,
      };

  String encode() => jsonEncode(toJson());

  static TransformativePlan decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const TransformativePlan();
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return const TransformativePlan();
      final modeName = json['mode'];
      final mode = TransformMode.values.where((v) => v.name == modeName).firstOrNull ??
          TransformMode.hybrid;
      final rawTools = json['tools'];
      final tools = <TransformTool>{};
      if (rawTools is List) {
        for (final value in rawTools) {
          if (value is String) {
            for (final tool in TransformTool.values) {
              if (tool.name == value) tools.add(tool);
            }
          }
        }
      }
      return TransformativePlan(
        version: 1,
        mode: mode,
        enabledTools: tools,
        instructions: json['instructions'] is String ? json['instructions'] as String : '',
      );
    } catch (_) {
      return const TransformativePlan();
    }
  }
}
