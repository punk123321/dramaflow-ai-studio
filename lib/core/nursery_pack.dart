/// A whole "episode pack" for an AI-made children's song video, made offline from a few choices: music prompt,
/// lyrics skeleton, character sheet prompt, scenes (picture prompt + animation prompt each) and YouTube title ideas.
/// The cast, presets, scene arc, title ideas and the remix idea come from the user's own KidsTube Pro starter
/// (merged here, see CHECKLIST TE-73). Differences from the starter: no brand or studio names in any prompt
/// (the style is described in plain words), the lyrics skeleton never pastes the topic sentence into a line,
/// the remix is repeatable (it takes a pick number) and every prompt carries the same safety rules as `nursery.dart`.
library;

import 'nursery.dart';

class NurseryCharacter {
  const NurseryCharacter(this.key, this.desc);

  /// The label shown in the screen (emoji + name).
  final String key;

  /// The full look, written into prompts so the character stays the same in every picture.
  final String desc;
}

const nurseryCharacters = <NurseryCharacter>[
  NurseryCharacter('👧 Mimi — Toddler Girl', 'Mimi, a cheerful 4-year-old toddler girl with big sparkling brown eyes, twin puff pigtails with yellow star hair clips, wearing a bright yellow star t-shirt and sky-blue denim dungarees'),
  NurseryCharacter('👦 Leo — Curious Boy', 'Leo, a friendly 4-year-old little boy with messy dark curly hair, rosy cheeks, wearing a striped red-and-white polo shirt and green shorts'),
  NurseryCharacter('🐶 Barnaby — Golden Puppy', 'Barnaby, a cute chubby baby golden retriever puppy with floppy ears, big sparkling eyes, wearing a tiny red bandana and blue denim overalls'),
  NurseryCharacter('🐱 Whiskers — Calico Kitten', 'Whiskers, an adorable fluffy calico kitten with big emerald eyes, wearing a pastel lavender collar with a tiny silver bell'),
  NurseryCharacter('🐰 Lulu — Baby White Bunny', 'Lulu, a soft fluffy white baby bunny with long pink-lined ears, wearing pastel lilac overalls with a star pocket'),
  NurseryCharacter('🐻 Pip — Baby Brown Bear', 'Pip, a round cuddly baby brown bear cub with big happy eyes, wearing a cozy red knit scarf and honey-yellow vest'),
  NurseryCharacter('🦆 Ducky — Yellow Duckling', 'Ducky, a cheerful bright yellow baby duckling with fluffy feathers, wearing a cute blue sailor hat'),
  NurseryCharacter('🐘 Ellie — Baby Blue Elephant', 'Ellie, an adorable baby pastel-blue elephant with big floppy ears, wearing a polka-dot bow tie'),
  NurseryCharacter('🐑 Baa-Baa — Fluffy Lamb', 'Baa-Baa, a super fluffy white baby lamb with big innocent eyes, wearing a mint-green ribbon bell'),
  NurseryCharacter('🚂 Choo-Choo Pip — Steam Train', 'Choo-Choo Pip, a smiling miniature pastel-blue and red steam locomotive train with big expressive cartoon eyes and a shiny golden bell'),
  NurseryCharacter('🤖 Bolt — Helper Robot', 'Bolt, a small rounded white-and-cyan friendly toddler robot with glowing heart-shaped LED eyes and bouncy wheels'),
  NurseryCharacter('🦖 Dino-Dan — Baby T-Rex', 'Dino-Dan, a cute chubby baby mint-green T-Rex dinosaur with soft orange back spikes and a striped scarf'),
  NurseryCharacter('⭐ Twinkle — Smiling Star', 'Twinkle, a glowing golden five-pointed baby star character with chubby cheeks and a tiny blue nightcap'),
  NurseryCharacter('🐘 ရွှေဆင်လေး (Shwe Sin)', 'Shwe Sin, a cute baby golden-brown Asian elephant with big happy eyes, wearing a traditional crimson-and-gold Myanmar festive vest and tiny golden bell collar'),
  NurseryCharacter('🎎 ဖိုးဝရုပ်လေး (Pho Wa)', 'Pho Wa, an adorable animated traditional Myanmar Pho Wa doll character with twin topknot hair buns, Thanaka patches on cheeks, wearing a colorful silk vest and paso'),
  NurseryCharacter('👧 ညီမလေး မေမေ (Myanmar Girl)', 'May May, a sweet 4-year-old Myanmar girl with neat Thanaka patches on her cheeks, white jasmine flowers in her hair, wearing a pastel pink traditional Myanmar blouse and htamein'),
];

String characterDesc(String key) {
  for (final c in nurseryCharacters) {
    if (c.key == key) return c.desc;
  }
  return '';
}

/// The tempo choices: label and beats per minute.
const nurseryTempos = <(String, int)>[
  ('Upbeat & Bouncy (118 BPM)', 118),
  ('Energetic Playful (124 BPM)', 124),
  ('Happy Walking (110 BPM)', 110),
  ('Gentle Sing-along (100 BPM)', 100),
  ('Calm Lullaby (76 BPM)', 76),
];

/// The tools that turn a picture into a short clip. Only used as a name inside the prompt.
const nurseryVideoTools = <String>['Google Flow (Veo)', 'Kling AI / Hailuo', 'Runway', 'Pika', 'Other image-to-video tool'];

class NurseryPreset {
  const NurseryPreset(this.label, this.topic, this.hero, this.friend1, this.friend2, this.lang, this.bpm, this.scenes, this.tool);

  final String label;
  final String topic;
  final String hero;
  final String friend1;
  final String friend2;
  final NurseryLang lang;
  final int bpm;
  final int scenes;
  final String tool;
}

const nurseryPresets = <NurseryPreset>[
  NurseryPreset('🐶 Happy Farm Band', 'Farm animal friends forming a joyful musical band in the sunny meadow, singing and playing instruments together', '🐶 Barnaby — Golden Puppy', '🦆 Ducky — Yellow Duckling', '🐑 Baa-Baa — Fluffy Lamb', NurseryLang.english, 118, 6, 'Google Flow (Veo)'),
  NurseryPreset('🪥 Brush Your Teeth', 'Fun morning routine song teaching toddlers how to brush their teeth up and down with bubbly foam', '👧 Mimi — Toddler Girl', '🐰 Lulu — Baby White Bunny', '🤖 Bolt — Helper Robot', NurseryLang.bilingual, 124, 6, 'Kling AI / Hailuo'),
  NurseryPreset('🇲🇲 မြန်မာ့ ကစားကွင်း', 'သနပ်ခါးပါးကွက်လေးတွေနဲ့ ညီမလေး၊ ရွှေဆင်လေးနဲ့ ဖိုးဝရုပ်လေးတို့ အတူတူ သီချင်းဆို ကခုန်ကြပုံ', '🐘 ရွှေဆင်လေး (Shwe Sin)', '👧 ညီမလေး မေမေ (Myanmar Girl)', '🎎 ဖိုးဝရုပ်လေး (Pho Wa)', NurseryLang.burmese, 115, 6, 'Google Flow (Veo)'),
];

/// What the person chose.
class NurseryPackInput {
  const NurseryPackInput({
    required this.topic,
    required this.hero,
    this.friend1 = '',
    this.friend2 = '',
    this.style = NurseryStyle.cartoon3d,
    this.lang = NurseryLang.english,
    this.bpm = 115,
    this.scenes = 6,
    this.ratio = '16:9',
    this.tool = 'Google Flow (Veo)',
    this.clipSeconds = 8,
  });

  final String topic;

  /// Full character looks (see [characterDesc]); [friend1] and [friend2] may be empty.
  final String hero;
  final String friend1;
  final String friend2;
  final NurseryStyle style;
  final NurseryLang lang;
  final int bpm;
  final int scenes;
  final String ratio;
  final String tool;
  final int clipSeconds;
}

class NurseryPackScene {
  const NurseryPackScene({
    required this.num,
    required this.startSec,
    required this.endSec,
    required this.action,
    required this.lyric,
    required this.imagePrompt,
    required this.videoPrompt,
  });

  final int num;
  final int startSec;
  final int endSec;
  final String action;

  /// The line to sing in this scene (a guide; the real lyrics come from the song).
  final String lyric;
  final String imagePrompt;
  final String videoPrompt;

  String get timestamp => '${_mmss(startSec)} - ${_mmss(endSec)}';
}

String _mmss(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

class NurseryPack {
  const NurseryPack({
    required this.musicPrompt,
    required this.lyrics,
    required this.characterPrompt,
    required this.scenes,
    required this.titles,
    required this.tags,
  });

  final String musicPrompt;
  final String lyrics;
  final String characterPrompt;
  final List<NurseryPackScene> scenes;
  final List<String> titles;
  final String tags;
}

String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The first part of a character look, up to the first comma ("Mimi, a cheerful ..." gives "Mimi").
String shortName(String desc) {
  final d = _clean(desc);
  if (d.isEmpty) return '';
  final i = d.indexOf(',');
  return (i < 0 ? d : d.substring(0, i)).trim();
}

/// At most [max] characters, cut at a space when there is one near the end. No "..." (titles stay clean).
String cutText(String s, int max) {
  final t = _clean(s);
  if (t.length <= max) return t;
  var cut = t.substring(0, max);
  final sp = cut.lastIndexOf(' ');
  if (sp > max * 0.6) cut = cut.substring(0, sp);
  return cut.trim();
}

class _Beat {
  const _Beat(this.action, this.lyric, this.everyone, this.camera);

  final String action;
  final String lyric;
  final bool everyone; // false = the hero only
  final String camera;
}

String _arcAction(int i, String hero, String cast, String topic) {
  switch (i % 9) {
    case 0:
      return '$hero waving warmly at the camera in a sunny opening welcome';
    case 1:
      return '$cast meeting up with joyful high-fives';
    case 2:
      return 'discovering colorful objects in the world of $topic';
    case 3:
      return 'energetic chorus dance with $cast clapping in rhythm';
    case 4:
      return 'interactive learning close-up with $hero counting clearly';
    case 5:
      return 'playful bubble surprise making $cast giggle';
    case 6:
      return 'teamwork moment where $cast help each other';
    case 7:
      return 'musical jam session with xylophone and mini drums';
    default:
      return 'grand finale celebration with balloons and a warm goodbye wave';
  }
}

_Beat _beat(int i, String hero, String cast, String topic) {
  final action = _arcAction(i, hero, cast, topic);
  switch (i % 9) {
    case 0:
      return _Beat(action, 'Hello friends! Come sing with $hero!', false, 'Slow dolly-in toward the main character waving happily');
    case 1:
      return _Beat(action, 'Look who is here! All our best friends!', true, 'Smooth pan revealing friends running into frame');
    case 2:
      return _Beat(action, 'Look over here! What did we find?', true, 'Tracking shot following the characters hopping playfully');
    case 3:
      return _Beat(action, 'Clap your hands, one, two, three!', true, 'Dynamic wide-angle circular orbit around the dancing group');
    case 4:
      return _Beat(action, "Let's count together — one, two, three!", false, 'Gentle zoom-in as the character points toward floating icons');
    case 5:
      return _Beat(action, 'Haha, look at those bouncing bubbles!', true, 'Playful upward tilt following floating bubbles');
    case 6:
      return _Beat(action, 'Helping friends makes every day bright!', true, 'Smooth side-scrolling shot along a rainbow path');
    case 7:
      return _Beat(action, 'Ting-a-ling and boom-boom-clap!', true, 'Energetic push-in matching the musical beats');
    default:
      return _Beat(action, 'Yay! Great job! Bye-bye friends!', true, 'Slow crane-up as colorful balloons rise into the sky');
  }
}

/// A short lyrics skeleton to start from. It does NOT contain the topic sentence. For real lyrics use the
/// lyrics prompt in `nursery.dart` and paste the answer.
String lyricsSkeleton(NurseryLang lang, String cast) {
  switch (lang) {
    case NurseryLang.burmese:
      return '[Intro]\nဟေး ဟေး ဟေး! $cast တို့ ရောက်လာပြီနော်!\n\n[Verse 1]\nနေရောင်ခြည်လေး လင်းလက်လာပြီ၊\nအတူတူ သီချင်းဆိုကြမယ်!\n\n[Chorus]\nလာလာလာ အတူတူ ကခုန်မယ်၊\nတစ်၊ နှစ်၊ သုံး၊ လေး လက်ခုပ်တီးမယ်!\n\n[Outro]\nတာ့တာ တာ့တာ နောက်မှတွေ့မယ်!';
    case NurseryLang.bilingual:
      return '[Intro]\nLa-la-la! $cast တို့နဲ့အတူ ဆိုကြမယ်!\n\n[Verse 1]\nLook around the sunny day, (နေရောင်ခြည်လေး လင်းလက်နေ)\nTime to sing and time to play!\n\n[Chorus]\nClap your hands, one, two, three! (လက်ခုပ်တီးမယ် တစ်၊ နှစ်၊ သုံး)\nDance and sing along with me!\n\n[Outro]\nWave goodbye, see you soon! (တာ့တာ နောက်မှတွေ့မယ်)';
    case NurseryLang.chinese:
      return '[Intro]\n嘿嘿嘿！$cast 来啦！\n\n[Verse 1]\n太阳公公笑哈哈，\n我们一起唱起来！\n\n[Chorus]\n拍拍手，一二三，\n一起跳舞一起唱！\n\n[Outro]\n再见再见，下次见！';
    case NurseryLang.english:
      return '[Intro]\nHey, hey, hey! Sing along with $cast!\n\n[Verse 1]\nWake up, wake up, see the morning sun,\nCome and sing, the day has begun!\n\n[Chorus]\nClap your hands, one, two, three!\nDance and sing along with me!\n\n[Outro]\nWave goodbye, we had such fun!';
  }
}

String _imagePrompt(NurseryPackInput x, int n, String who, String action, String topic) {
  return "Children's animation frame, ${x.ratio}. ${x.style.english}. Scene $n: $who, $action, in the world of $topic. "
      'Use the attached character sheet and keep the same faces, colors and clothes. Soft rim lighting, one clear focal point, simple uncluttered background, safe for toddlers. '
      'No text, no letters, no watermark, no scary elements, no real people, no existing cartoon characters or logos.';
}

String _videoPrompt(NurseryPackInput x, String action, String camera, String lyric) {
  return buildVideoPrompt(sceneText: lyric, camera: camera, style: x.style, seconds: x.clipSeconds, character: '')
      .replaceFirst('the main character moves happily to match', 'the characters move happily to match')
      .replaceFirst('Animate the attached picture', 'Animate the attached picture (${action.isEmpty ? 'scene' : action})')
      .replaceFirst('into a ${x.clipSeconds}-second', 'into a ${x.clipSeconds}-second (for ${x.tool})');
}

/// Makes the whole pack. Pure and repeatable: the same choices give the same pack.
NurseryPack buildPack(NurseryPackInput x) {
  final hero = _clean(x.hero);
  final f1 = _clean(x.friend1);
  final f2 = _clean(x.friend2);
  final heroName = shortName(hero).isEmpty ? 'Hero' : shortName(hero);
  final names = [heroName, if (shortName(f1).isNotEmpty) shortName(f1), if (shortName(f2).isNotEmpty) shortName(f2)];
  final castNames = names.join(', ');
  final castFull = hero.isEmpty ? heroName : '$hero${f1.isEmpty ? '' : ' alongside $f1'}${f2.isEmpty ? '' : ' and $f2'}';
  final topic = cutText(x.topic, 60);
  final n = x.scenes.clamp(4, 9).toInt();
  final clip = x.clipSeconds.clamp(3, 12).toInt();

  final scenes = <NurseryPackScene>[];
  for (var i = 0; i < n; i++) {
    final b = _beat(i, heroName, castNames, topic);
    final who = b.everyone ? castFull : (hero.isEmpty ? heroName : hero);
    scenes.add(NurseryPackScene(
      num: i + 1,
      startSec: i * clip,
      endSec: (i + 1) * clip,
      action: b.action,
      lyric: b.lyric,
      imagePrompt: _imagePrompt(x, i + 1, who, b.action, topic),
      videoPrompt: _videoPrompt(x, b.action, b.camera, b.lyric),
    ));
  }

  return NurseryPack(
    musicPrompt: buildMusicPrompt(lang: x.lang, bpm: x.bpm),
    lyrics: lyricsSkeleton(x.lang, castNames),
    characterPrompt: buildCharacterPrompt(character: hero, style: x.style),
    scenes: scenes,
    titles: [
      '${cutText(x.topic, 45)} | Nursery Rhymes & Kids Songs | $heroName',
      'Clap & Sing Along! 🎵 ${cutText(x.topic, 40)} | Toddler Animation',
    ],
    tags: 'nursery rhymes, kids songs, toddler learning, ${heroName.toLowerCase()}, sing along, kids animation',
  );
}

const _remixes = <(String, String, String)>[
  ('{h} and friends dancing under a glowing rainbow arch', 'Look up high at the rainbow bright!', 'Crane-up orbit around the joyful dancing characters'),
  ('playful peek-a-boo behind giant colorful flowers', 'Peek-a-boo! I see you! Clap your hands!', 'Bouncy zoom-in as the characters pop out smiling'),
  ('floating on a fluffy pastel cloud boat across a starry sky', 'Floating softly way up high!', 'Dreamy gliding tracking shot alongside the cloud boat'),
];

/// A new idea for one scene. [pick] chooses one of three ready ideas (the same pick gives the same result);
/// a non-empty [note] is used as the action instead. Other scenes are not touched.
NurseryPackScene remixScene(NurseryPackScene old, NurseryPackInput x, {String note = '', int pick = 0}) {
  final hero = _clean(x.hero);
  final heroName = shortName(hero).isEmpty ? 'Hero' : shortName(hero);
  final r = _remixes[pick.abs() % _remixes.length];
  final action = _clean(note).isNotEmpty ? _clean(note) : r.$1.replaceAll('{h}', heroName);
  final cast = [hero, _clean(x.friend1), _clean(x.friend2)].where((e) => e.isNotEmpty).join(' alongside ');
  return NurseryPackScene(
    num: old.num,
    startSec: old.startSec,
    endSec: old.endSec,
    action: action,
    lyric: r.$2,
    imagePrompt: _imagePrompt(x, old.num, cast.isEmpty ? heroName : cast, action, cutText(x.topic, 60)),
    videoPrompt: _videoPrompt(x, action, r.$3, r.$2),
  );
}
