import 'timeline.dart';

/// Ready-made subtitle looks. Applying one replaces size, colour, background,
/// position and fade; the user can still change each of them afterwards.
class SubPreset {
  const SubPreset(this.id, this.label, this.style);

  final String id;
  final String label;
  final SubStyle style;
}

const subPresets = <SubPreset>[
  SubPreset('classic', 'ပုံမှန်', SubStyle()),
  SubPreset('big_yellow', 'အကြီး အဝါ', SubStyle(size: 0.065, color: 0xFFFFD84D)),
  SubPreset('clean', 'သန့်သန့် (နောက်ခံမပါ)', SubStyle(size: 0.05, background: false, fade: true)),
  SubPreset('soft', 'ညင်သာ (fade)', SubStyle(size: 0.045, fade: true)),
  SubPreset('top', 'အပေါ်ဆုံး', SubStyle(size: 0.045, top: true)),
];

/// The preset whose style equals [s], or null when the user changed something.
SubPreset? matchingPreset(SubStyle s) {
  for (final p in subPresets) {
    final q = p.style;
    if (q.size == s.size && q.color == s.color && q.background == s.background && q.top == s.top && q.fade == s.fade) return p;
  }
  return null;
}
