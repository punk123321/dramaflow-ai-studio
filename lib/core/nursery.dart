/// Helpers for an AI-made children's song video (a nursery rhyme with pictures). The app does not make the
/// song or the pictures itself: it writes the prompts for the AI tools the person already uses, splits the
/// lyrics into scenes and later joins the finished song and pictures into a video (on the Colab backend).
/// Everything here is plain text work and is tested without a phone.
library;

import 'dart:convert';

/// What the song is about.
enum NurseryTheme {
  animals('တိရစ္ဆာန်လေးတွေ', 'friendly farm and forest animals'),
  numbers('ဂဏန်း ရေတွက်', 'counting from one to ten'),
  colors('အရောင်တွေ', 'learning colors'),
  abc('အက္ခရာ / စာလုံး', 'learning the alphabet'),
  bedtime('အိပ်ရာဝင် သီချင်း', 'a gentle bedtime lullaby'),
  habits('အကျင့်ကောင်း (သွားတိုက်၊ လက်ဆေး)', 'good daily habits like brushing teeth and washing hands'),
  vehicles('ကား / ရထား / လေယာဉ်', 'cars, trains and airplanes'),
  family('မိသားစု / သူငယ်ချင်း', 'family and friends'),
  custom('ကိုယ်ပိုင်ခေါင်းစဉ်', '');

  const NurseryTheme(this.label, this.english);

  final String label;
  final String english;
}

/// The look of the pictures.
enum NurseryStyle {
  cartoon3d('3D cartoon', 'cute 3D animated cartoon, soft rounded shapes, bright cheerful colors, smooth lighting'),
  flat2d('2D flat cartoon', 'simple flat 2D cartoon, bold outlines, bright primary colors, clean shapes'),
  storybook('Watercolor storybook', 'soft watercolor children\'s storybook illustration, warm pastel colors, gentle textures'),
  paperCut('Paper-cut / craft', 'colorful layered paper-cut craft style, handmade look, soft shadows'),
  clay('Clay / stop-motion', 'soft handmade claymation stop-motion look, tactile clay texture, warm studio lighting, gentle rounded shapes');

  const NurseryStyle(this.label, this.english);

  final String label;
  final String english;
}

/// The language the song is sung in.
enum NurseryLang {
  english('English', 'English'),
  burmese('မြန်မာ', 'Burmese (Myanmar language, written in Myanmar script)'),
  chinese('中文', 'Simplified Chinese'),
  bilingual('English + မြန်မာ', 'English and Burmese (each line in English followed by its Burmese meaning in brackets)');

  const NurseryLang(this.label, this.words);

  final String label;

  /// How the language is named in a prompt.
  final String words;
}

/// The music style (from the user's v3 notebook). [words] goes into the song prompts.
enum NurseryGenre {
  kidsPop('🎉 Upbeat Kids Pop & Ukulele', 'upbeat kids pop with ukulele, bright, bouncy, catchy hook'),
  dancePop('💃 Funky Dance Party Pop', 'funky dance party pop, groovy bass, hand claps, energetic'),
  comedy('😂 Playful Cartoon Comedy', 'playful cartoon comedy bounce, silly, xylophone, slide whistle'),
  march('🥁 Cheerful Marching Band', 'cheerful marching band, snare drum, brass, counting rhythm'),
  island('🌴 Tropical Sunny Island Beat', 'relaxed tropical island beat, marimba, happy'),
  lullaby('🌙 Gentle Bedtime Lullaby', 'gentle acoustic lullaby, music box, soft guitar, dreamy'),
  synth('🚀 Synth-Pop Adventure', 'synth-pop space adventure, sparkly synths, exciting'),
  festive('🇲🇲 Myanmar Festive Kids Vibe', 'Myanmar traditional festive kids vibe, cheerful drums, xylophone, warm');

  const NurseryGenre(this.label, this.words);

  final String label;
  final String words;
}

/// Song ideas for the 🎲 button (the user's own list from the v3 notebook).
const nurserySongIdeas = <String>[
  'Silly Monkey Lost His Banana — funny counting & sharing adventure in the jungle',
  'Bubbly Brush Your Teeth Party — energetic morning routine brushing up and down',
  'Freeze Dance Dinosaur Stomp — fun action song where kids dance and freeze like statues',
  'The Sneezing Baby Elephant — hilarious musical story about covering sneezes and giggling',
  '1-2-3 Space Rocket Blast Off — counting planets and stars on a rainbow spaceship',
  'Wash Your Hands Splash Song — soapy bubbles washing away sneaky little germs',
  'Color Mixing Magic Paint — mixing red, yellow, and blue to discover rainbow colors',
  'Clean Up Toy Train — cheerful helper song putting toys away before playtime ends',
  'Who Ate the Rainbow Cookie? — playful mystery rhyme with cute animal friends',
  'Jump Like a Frog, Flap Like a Duck — animal movement workout song for toddlers',
  'Goodnight Little Glowing Star — dreamy calm bedtime lullaby floating on pastel clouds',
  'Wheels on the Rainbow Bus — classic upbeat ride through candy hills and sunny meadows',
  'သနပ်ခါးပါးကွက်လေးနဲ့ ကျောင်းသွားမယ် — cheerful Myanmar morning school routine song',
  'ရွှေဆင်လေးရဲ့ ပျော်ပွဲရွှင်ပွဲ — playful Myanmar animal friends singing and dancing together',
  'လက်ဆေးကြမယ် ရေပူဖောင်းလေးတွေ — fun Burmese & English bilingual hand-washing song',
];

String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

String _topic(NurseryTheme theme, String custom) {
  final c = _clean(custom);
  if (theme == NurseryTheme.custom || (c.isNotEmpty && theme.english.isEmpty)) return c.isEmpty ? 'a simple everyday topic for toddlers' : c;
  return c.isEmpty ? theme.english : '${theme.english} ($c)';
}

/// Asks a text AI for ORIGINAL lyrics. The answer format is fixed so that [splitScenes] can read it.
String buildLyricsPrompt({
  NurseryTheme theme = NurseryTheme.animals,
  String custom = '',
  NurseryLang lang = NurseryLang.english,
  int verses = 3,
  String character = '',
  NurseryGenre? genre,
  String tempo = '',
  String twist = '',
  bool withStyle = false,
}) {
  final n = verses.clamp(1, 8).toInt();
  final who = _clean(character);
  final b = StringBuffer();
  b.writeln('Write the lyrics of a NEW, ORIGINAL nursery rhyme for toddlers (ages 2 to 5) about: ${_topic(theme, custom)}.');
  b.writeln('Language: ${lang.words}.');
  if (who.isNotEmpty) b.writeln('Main character (use this name): $who.');
  if (withStyle) {
    if (genre != null) b.writeln('Music genre and vibe: ${genre.words}.');
    if (_clean(tempo).isNotEmpty) b.writeln('Tempo / mood: ${_clean(tempo)}.');
    if (_clean(twist).isNotEmpty) b.writeln('Special creative twist: ${_clean(twist)}.');
  }
  b.writeln('Structure: $n verses of 4 short lines each, plus a 2-line chorus repeated after every verse. Very simple words, strong rhyme, a steady sing-along rhythm, easy to repeat, gentle and happy.');
  b.writeln('Rules: do not copy or paraphrase any existing song, rhyme, character or brand. Nothing scary, violent or unsafe, no real names. No advertising and no web links.');
  if (withStyle) {
    b.writeln('Put simple animation action cues in their own line in parentheses, for example (clap hands) or (jump high), so the scenes are easy to animate.');
    b.writeln('Output format, exactly (no other text, no explanations):');
    b.writeln('SUNO STYLE:');
    b.writeln('(English only, under 180 characters: the exact BPM, specific instruments, the vocal style, a clean studio mix. Do not name any artist, song or brand)');
    b.writeln('');
    b.writeln('LYRICS:');
    b.writeln('[Intro]');
    b.writeln('...');
    b.writeln('[Verse 1]');
    b.writeln('...');
    b.writeln('[Chorus]');
    b.writeln('...');
    b.writeln('[Verse 2]');
    b.writeln('...');
    b.writeln('[Action break]');
    b.writeln('...');
    b.writeln('[Final Chorus]');
    b.writeln('...');
    b.write('[Outro]');
    return b.toString();
  }
  b.writeln('Output format, exactly (no other text, no explanations, no markdown):');
  b.writeln('[Verse 1]');
  b.writeln('line');
  b.writeln('line');
  b.writeln('line');
  b.writeln('line');
  b.writeln('');
  b.writeln('[Chorus]');
  b.writeln('line');
  b.writeln('line');
  b.writeln('');
  b.write('(then [Verse 2], [Chorus], and so on)');
  return b.toString();
}

/// Style words for a music AI (Suno, Udio and similar). No artist or song names on purpose.
String buildMusicPrompt({NurseryLang lang = NurseryLang.english, int bpm = 100, bool female = true, String mood = 'cheerful', NurseryGenre? genre}) {
  final m = _clean(mood).isEmpty ? 'cheerful' : _clean(mood);
  final b = StringBuffer();
  b.writeln("$m children's nursery rhyme, simple catchy melody, ${female ? 'warm friendly female' : 'warm friendly male'} vocal, ${lang.words.split(' ').first} lyrics,");
  final gentle = bpm <= 80 || genre == NurseryGenre.lullaby;
  b.writeln(gentle
      ? 'music box, warm acoustic guitar, soft glockenspiel, soothing, dreamy, $bpm BPM, gentle sing-along, major key, clean studio mix, no explicit content.'
      : 'ukulele, glockenspiel, soft claps and light percussion, $bpm BPM, sing-along, major key, clean and bright, no explicit content.');
  if (genre != null) b.writeln('Style: ${genre.words}.');
  b.write('Original melody. Do not imitate any existing song, artist or brand.');
  return b.toString();
}

/// A character sheet picture prompt: make the main character once, then reuse it as the reference picture.
String buildCharacterPrompt({String character = '', NurseryStyle style = NurseryStyle.cartoon3d}) {
  final who = _clean(character).isEmpty ? 'a cute friendly little bunny with big round eyes, a tiny blue scarf and a happy smile' : _clean(character);
  return 'Character sheet of an ORIGINAL children\'s cartoon character: $who. '
      'Show front view, side view and a happy expression on a plain light background. ${style.english}. '
      'Friendly and safe for toddlers, simple design that is easy to draw again. '
      'Do not copy any existing cartoon character, brand or logo. No text, no letters, no watermark.';
}

/// One picture prompt for one scene. [sceneText] is the lyric of the scene; the character text keeps the look the same in every picture.
String buildScenePrompt({
  required String sceneText,
  String character = '',
  NurseryStyle style = NurseryStyle.cartoon3d,
  bool hasReferenceImage = true,
  String ratio = '16:9',
}) {
  final who = _clean(character);
  final b = StringBuffer();
  b.write('Children\'s animation frame, $ratio. ${style.english}. ');
  b.write('Illustrate this song line as a happy scene: "${_clean(sceneText)}". ');
  if (hasReferenceImage) b.write('Use the attached character sheet as the main character and keep the same face, colors and clothes. ');
  if (who.isNotEmpty) b.write('Main character: $who. ');
  b.write('One clear focal point, simple uncluttered background, safe for toddlers. ');
  b.write('No text, no letters, no watermark, no scary elements, no real people, no existing cartoon characters or logos.');
  return b.toString();
}

/// How a still picture moves when an image-to-video AI (Veo, Kling, Runway, Pika and similar) animates it.
/// Each scene gets a different camera move in turn, so the video does not feel repeated.
const nurseryMoves = <String>[
  'slow gentle zoom in toward the character',
  'slow pan from left to right',
  'soft zoom out to show the whole scene',
  'slow pan from right to left',
  'slight upward tilt with floating sparkles',
];

/// A short image-to-video prompt for scene [index]: the attached scene picture comes alive (a few seconds of
/// simple, safe movement). The picture is the first frame; nothing new is added.
String buildVideoPrompt({
  required String sceneText,
  int index = 0,
  String camera = '',
  String character = '',
  NurseryStyle style = NurseryStyle.cartoon3d,
  int seconds = 5,
}) {
  final who = _clean(character);
  final move = _clean(camera).isNotEmpty ? _clean(camera) : nurseryMoves[index.abs() % nurseryMoves.length];
  final b = StringBuffer();
  b.write('Animate the attached picture into a $seconds-second children\'s cartoon clip. Keep the same ${style.english} look, characters, colors and background. ');
  b.write('Action: ${who.isEmpty ? 'the main character' : who} moves happily to match the song line "${_clean(sceneText)}" (small bouncing, waving, blinking, swaying). ');
  b.write('Camera: $move. Smooth, calm, simple motion. ');
  b.write('No new characters, no text, no morphing faces, no sudden cuts, nothing scary, no existing cartoon characters or logos.');
  return b.toString();
}

/// One part of the song that gets one picture.
class NurseryScene {
  const NurseryScene({required this.label, required this.lines});

  final String label;
  final List<String> lines;

  String get text => lines.join(' / ');
}

final _tag = RegExp(r'^\s*[\[（【]\s*([^\]）】]{1,40}?)\s*[\]）】]\s*:?\s*$');

/// "(clap hands)" on a line of its own (plain ASCII only) is an animation cue for the person, not a sung line.
final _cue = RegExp(r'^\(\s*[\x20-\x7E]{1,60}\)$');

/// Reads the lyrics an AI wrote. A scene starts at a "[Verse 1]" style heading or after a blank line.
/// Headings are kept as labels and are not sung; a line that is only a cue such as "(clap hands)" is dropped. Stray markdown (**, #, -) is removed. At most [maxScenes] scenes
/// (the rest are added to the last one so no lyric line is lost).
List<NurseryScene> splitScenes(String lyrics, {int maxScenes = 40}) {
  final out = <NurseryScene>[];
  var label = '';
  var cur = <String>[];
  var n = 0;
  void flush() {
    if (cur.isNotEmpty) {
      n++;
      out.add(NurseryScene(label: label.isEmpty ? 'Scene $n' : label, lines: cur));
    }
    cur = <String>[];
    label = '';
  }

  for (var raw in lyrics.split(RegExp(r'\r?\n'))) {
    raw = raw.replaceAll(RegExp(r'[*_`#]+'), '').replaceFirst(RegExp(r'^\s*[-•]\s+'), '');
    final line = raw.trim();
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (_cue.hasMatch(line)) continue;
    final m = _tag.firstMatch(line);
    if (m != null) {
      flush();
      label = m.group(1)!.trim();
      continue;
    }
    cur.add(line);
  }
  flush();
  if (out.length > maxScenes) {
    final keep = out.sublist(0, maxScenes - 1);
    final rest = [for (final s in out.sublist(maxScenes - 1)) ...s.lines];
    keep.add(NurseryScene(label: out[maxScenes - 1].label, lines: rest));
    return keep;
  }
  return out;
}

/// What an AI answered to the songwriter prompt: the style text for the song AI and the lyrics.
class NurseryAnswer {
  const NurseryAnswer({this.style = '', required this.lyrics});

  final String style;
  final String lyrics;
}

String _unfence(String t) => t.replaceAll(RegExp(r'```[a-zA-Z]*'), '').trim();

/// Splits a pasted answer into "SUNO STYLE:" and "LYRICS:" (also "STYLE PROMPT:", "SONG LYRICS:", with **bold** or ###).
/// Without a LYRICS heading the lyrics start at the first [Intro] / [Verse]; with no sign of either the whole text
/// is the lyrics, so a plain pasted song always works.
NurseryAnswer splitSongAnswer(String raw) {
  final text = raw.replaceAll('\r\n', '\n').trim();
  if (text.isEmpty) return const NurseryAnswer(lyrics: '');
  var style = '';
  var lyrics = text;
  final head = RegExp(r'^[ \t]*(?:\*\*|#{1,4}\s*)?(?:SUNO\s*STYLE|STYLE\s*PROMPT|STYLE)(?:\*\*)?\s*:?(?:\*\*)?[ \t]*\n?', caseSensitive: false, multiLine: true);
  final lyr = RegExp(r'^[ \t]*(?:\*\*|#{1,4}\s*)?(?:SONG\s*LYRICS|LYRICS)(?:\*\*)?\s*:?(?:\*\*)?[ \t]*\n', caseSensitive: false, multiLine: true);
  final lm = lyr.firstMatch(text);
  if (lm != null) {
    lyrics = _unfence(text.substring(lm.end));
    final before = text.substring(0, lm.start);
    final sm = head.firstMatch(before);
    if (sm != null) style = _unfence(before.substring(sm.end)).replaceAll(RegExp(r'\s+'), ' ').trim();
  } else {
    final tag = RegExp(r'\[\s*(?:Intro|Verse)', caseSensitive: false).firstMatch(text);
    if (tag != null) {
      lyrics = _unfence(text.substring(tag.start));
      final before = text.substring(0, tag.start);
      final sm = head.firstMatch(before);
      if (sm != null) style = _unfence(before.substring(sm.end)).replaceAll(RegExp(r'\s+'), ' ').trim();
    } else {
      lyrics = _unfence(text);
    }
  }
  return NurseryAnswer(style: style, lyrics: lyrics);
}

/// Seconds for each scene when no real timing is known: the song length is shared by the number of lyric
/// lines in each scene (a scene with more lines lasts longer). Every scene gets at least [minSec].
List<double> equalTimes(List<NurseryScene> scenes, double songSec, {double minSec = 1.5}) {
  if (scenes.isEmpty || songSec <= 0) return const [];
  final weights = [for (final s in scenes) s.lines.isEmpty ? 1 : s.lines.length];
  final total = weights.fold<int>(0, (a, b) => a + b);
  final raw = [for (final w in weights) songSec * w / total];
  // lift the short ones to the minimum, taking the extra from the long ones in proportion
  final floor = songSec / scenes.length < minSec ? songSec / scenes.length : minSec;
  var deficit = 0.0;
  var spare = 0.0;
  for (final r in raw) {
    if (r < floor) {
      deficit += floor - r;
    } else {
      spare += r - floor;
    }
  }
  if (deficit <= 0 || spare <= 0) return raw;
  final k = deficit > spare ? 1.0 : deficit / spare;
  return [for (final r in raw) r < floor ? floor : r - (r - floor) * k];
}


// ---------------------------------------------------------------------------------------------
// From the user's own "KidsTube Pro" starter (character library, presets, scene arc, SEO), ported to
// Dart so it works offline in the app. The brand name that starter put in its style text was left out
// on purpose: the look is described in plain words, never "like <an existing show>".
// ---------------------------------------------------------------------------------------------

/// A ready character the person can cast. [desc] is the English text sent to the picture / video AI.
class NurseryCharacter {
  const NurseryCharacter(this.label, this.desc);

  final String label;
  final String desc;

  /// "Mimi" from "Mimi, a cheerful ..." (the words before the first comma).
  String get shortName {
    final i = desc.indexOf(',');
    final n = (i < 0 ? desc : desc.substring(0, i)).trim();
    return n.isEmpty ? 'Hero' : n;
  }
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
  NurseryCharacter('🎎 ဖိုးဝရုပ်လေး (Pho Wa)', 'Pho Wa, an adorable 3D animated traditional Myanmar Pho Wa doll character with twin topknot hair buns, Thanaka patches on cheeks, wearing a colorful silk vest and paso'),
  NurseryCharacter('👧 ညီမလေး မေမေ (Myanmar Girl)', 'May May, a sweet 4-year-old Myanmar girl with neat Thanaka patches on her cheeks, white jasmine flowers in her hair, wearing a pastel pink traditional Myanmar blouse and htamein'),
  NurseryCharacter('👫 Maya & Max — Twin Siblings', 'Maya and Max, adorable 4-year-old twin sister and brother with matching joyful smiles, Maya in a pink polka-dot dress and Max in a blue rocket-ship sweater'),
  NurseryCharacter('👩‍🏫 Miss Clara — Preschool Teacher', 'Miss Clara, a warm and expressive young preschool teacher with round glasses, braided hair, wearing a pastel mint cardigan over a floral dress'),
  NurseryCharacter('👨‍👩‍👧 Mommy & Daddy — Loving Parents', 'Mommy and Daddy, friendly warm-hearted young parents with gentle smiles, casual colorful pastel sweaters, encouraging and caring expressions'),
  NurseryCharacter('🦁 Leo Jr. — Baby Lion Cub', 'Leo Jr., a cute baby lion cub with a tiny fluffy orange tuft mane, big amber eyes, wearing a miniature explorer vest'),
  NurseryCharacter('🐵 Momo — Silly Little Monkey', 'Momo, a playful baby brown monkey with big expressive ears, curly tail, wearing a bright yellow banana-patterned t-shirt'),
  NurseryCharacter('🚒 Ember — Little Fire Truck', 'Ember, a cute chibi red fire truck with big friendly windshield eyes, a cheerful bumper smile, shiny yellow ladder, and glowing blue siren light'),
  NurseryCharacter('🚌 Sunny — Yellow School Bus', 'Sunny, a bright yellow rounded chibi school bus with big joyful cartoon eyes, rosy headlights, and a friendly wave from its side mirror'),
  NurseryCharacter('☁️ Nimbus — Fluffy Happy Cloud', 'Nimbus, a soft floating white-and-pastel-pink baby cloud character with cute rosy cheeks and a tiny rainbow crown'),
  NurseryCharacter('🧚 Luna — Tiny Garden Fairy', 'Luna, a cute miniature toddler garden fairy with translucent shimmering butterfly wings, flower-petal dress, and a glowing dandelion wand'),
  NurseryCharacter('👦 မောင်လေး အောင်အောင် (Myanmar Boy)', 'Aung Aung, a cheerful 4-year-old Myanmar boy with round Thanaka cheek patches, bright eyes, wearing a traditional white collarless shirt (taikpon) and colorful checkered longyi'),
];

/// Tempo choices (the number is the BPM written into the music prompt).
const nurseryTempos = <String>[
  'Upbeat & Bouncy (118 BPM)',
  'Energetic Playful (124 BPM)',
  'Gentle & Sweet (96 BPM)',
  'Lullaby (72 BPM)',
  'Cheerful Marching (112 BPM)',
  'Calm Lullaby (76 BPM)',
];

/// The image-to-video tools the video prompt is tuned for (the name is only written into the prompt).
const nurseryVideoTools = <String>['Google Flow (Veo 3.1)', 'Kling AI / Hailuo', 'Runway', 'Pika', 'Vidu / PixVerse'];

/// The BPM written in a tempo text such as "Upbeat & Bouncy (118 BPM)"; [fallback] when there is none.
int bpmOf(String tempo, {int fallback = 115}) {
  final m = RegExp(r'(\d{2,3})\s*BPM', caseSensitive: false).firstMatch(tempo);
  final v = m == null ? null : int.tryParse(m.group(1)!);
  return v == null || v < 40 || v > 220 ? fallback : v;
}

/// A one-tap set of choices.
class NurseryPreset {
  const NurseryPreset({
    required this.label,
    required this.topic,
    required this.hero,
    this.friend1,
    this.friend2,
    this.lang = NurseryLang.english,
    this.tempo = 'Upbeat & Bouncy (118 BPM)',
    this.videoTool = 'Google Flow (Veo 3.1)',
    this.scenes = 6,
    this.style = NurseryStyle.cartoon3d,
  });

  final String label;
  final String topic;
  final int hero;
  final int? friend1;
  final int? friend2;
  final NurseryLang lang;
  final String tempo;
  final String videoTool;
  final int scenes;
  final NurseryStyle style;
}

/// Indexes point into [nurseryCharacters].
const nurseryPresets = <NurseryPreset>[
  NurseryPreset(
    label: '🐶 Happy Farm Band',
    topic: 'Farm animal friends forming a joyful musical band in the sunny meadow, singing and playing instruments together',
    hero: 2,
    friend1: 6,
    friend2: 8,
  ),
  NurseryPreset(
    label: '🪥 Brush Your Teeth',
    topic: 'Fun morning routine song teaching toddlers how to brush their teeth up and down with bubbly foam',
    hero: 0,
    friend1: 4,
    friend2: 10,
    tempo: 'Energetic Playful (124 BPM)',
    videoTool: 'Kling AI / Hailuo',
  ),
  NurseryPreset(
    label: '🇲🇲 မြန်မာ့ ကစားကွင်း',
    topic: 'သနပ်ခါးပါးကွက်လေးတွေနဲ့ ညီမလေး၊ ရွှေဆင်လေးနဲ့ ဖိုးဝရုပ်လေးတို့ အတူတူ သီချင်းဆို ကခုန်ကြပုံ',
    hero: 13,
    friend1: 15,
    friend2: 14,
    lang: NurseryLang.burmese,
    tempo: 'Upbeat & Bouncy (115 BPM)',
  ),
  NurseryPreset(
    label: '🚂 Rainbow Counting Train',
    topic: 'A magical rainbow steam train picking up cute friends and counting colorful fruits from 1 to 5 across candy hills',
    hero: 9,
    friend1: 5,
    friend2: 11,
    tempo: 'Cheerful Marching (112 BPM)',
    scenes: 8,
    style: NurseryStyle.clay,
  ),
  NurseryPreset(
    label: '🌙 Bedtime Stars Lullaby',
    topic: 'Gentle bedtime lullaby saying goodnight to the glowing moon, sleepy clouds, and twinkling stars',
    hero: 4,
    friend1: 12,
    friend2: 23,
    lang: NurseryLang.bilingual,
    tempo: 'Calm Lullaby (76 BPM)',
    style: NurseryStyle.storybook,
  ),
];

/// "Hero alongside Friend1 and Friend2" for a picture prompt; empty parts are left out.
String castText(String hero, [String friend1 = '', String friend2 = '']) {
  final h = _clean(hero);
  final a = _clean(friend1);
  final b = _clean(friend2);
  return h + (a.isEmpty ? '' : ' alongside $a') + (b.isEmpty ? '' : ' and $b');
}

/// One beat of the story the scenes follow (the starter's arc, 12 steps from the v3 notebook; the last one is always the goodbye). [camera] is the move for the video tool.
class NurseryBeat {
  const NurseryBeat(this.action, this.line, this.camera, {this.heroOnly = false});

  final String action; // {cast} and {hero} are replaced
  final String line; // a short default line shown under the scene when no lyrics are given
  final String camera;
  final bool heroOnly; // only the hero is in this shot
}

const nurseryArc = <NurseryBeat>[
  NurseryBeat('{hero} waving warmly at camera in a sunny opening welcome', 'Hello friends! Come sing with {hero}!', 'Slow dolly-in toward the main character waving happily', heroOnly: true),
  NurseryBeat('{cast} meeting up with joyful high-fives', 'Look who is here! All our best friends!', 'Smooth pan revealing friends running into frame'),
  NurseryBeat('{cast} discovering colorful objects for {topic}', 'Look over here! What did we find?', 'Tracking shot following the characters hopping playfully'),
  NurseryBeat('Energetic chorus dance with {cast} clapping in rhythm', 'Clap your hands, one, two, three!', 'Dynamic wide-angle circular orbit around the dancing group'),
  NurseryBeat('Interactive learning close-up with {hero} counting clearly', "Let's count together — one, two, three!", 'Gentle zoom-in as the character points toward floating icons', heroOnly: true),
  NurseryBeat('Playful bubble surprise making {cast} giggle', 'Haha, look at those bouncing bubbles!', 'Playful upward tilt following floating bubbles'),
  NurseryBeat('Teamwork moment where {cast} help each other', 'Helping friends makes every day bright!', 'Smooth side-scrolling shot along a rainbow path'),
  NurseryBeat('Musical jam session with xylophone and mini drums', 'Ting-a-ling and boom-boom-clap!', 'Energetic push-in matching musical beats'),
  NurseryBeat('Big second chorus jump party under a pastel rainbow arch with {cast}', 'Jump up high and spin around!', 'Wide sweeping crane shot capturing joyful leaps'),
  NurseryBeat('Sweet sharing and kindness close-up with warm hugs between {cast}', 'Sharing kindness, sharing cheer!', 'Warm slow dolly-in with golden rim lighting'),
  NurseryBeat('Celebration buildup with pastel balloons and twinkling stars for {cast}', 'Hooray! You did an amazing job!', 'Lively upward tilt following rising balloons'),
  NurseryBeat('Grand finale celebration with balloons and warm goodbye wave', 'Yay! Great job! Bye-bye friends!', 'Slow crane-up as colorful balloons rise into sky'),
];

/// Which beats of the arc a plan of [n] scenes uses: always the welcome first and the goodbye last, the rest spread
/// evenly between them without repeating (the v3 notebook's rule). Above 12 the arc repeats.
List<int> arcPick(int n) {
  final len = nurseryArc.length;
  if (n <= 0) return const [];
  if (n == 1) return const [0];
  if (n > len) return [for (var i = 0; i < n; i++) i % len];
  if (n == len) return [for (var i = 0; i < len; i++) i];
  final mids = n - 2;
  final used = <int>{0, len - 1};
  final out = <int>[];
  final step = (len - 2) / mids;
  for (var j = 0; j < mids; j++) {
    var c = (1 + (j * step).round()).clamp(1, len - 2).toInt();
    while (used.contains(c) && c < len - 2) {
      c++;
    }
    while (used.contains(c) && c > 1) {
      c--;
    }
    used.add(c);
    out.add(c);
  }
  out.sort();
  return [0, ...out, len - 1];
}

/// One scene of the finished plan: what happens, the line under it, and the two prompts.
class NurseryPackScene {
  const NurseryPackScene({
    required this.number,
    required this.action,
    required this.line,
    required this.imagePrompt,
    required this.videoPrompt,
  });

  final int number;
  final String action;
  final String line;
  final String imagePrompt;
  final String videoPrompt;
}

/// The scene plan: [count] scenes (4 to 12 unless [minCount] / [maxCount] say otherwise; the arc repeats if needed). When [lyricScenes] are given their text becomes
/// the line of each scene in order (a scene without lyrics keeps the arc's line). The topic is shortened to
/// 60 characters inside the action text so a long Burmese sentence does not swamp the prompt.
List<NurseryPackScene> buildPackScenes({
  required String topic,
  required String hero,
  String friend1 = '',
  String friend2 = '',
  int count = 6,
  int minCount = 4,
  int maxCount = 12,
  NurseryStyle style = NurseryStyle.cartoon3d,
  String ratio = '16:9',
  String videoTool = 'Google Flow (Veo 3.1)',
  List<NurseryScene> lyricScenes = const [],
}) {
  final n = count.clamp(minCount, maxCount).toInt();
  final cast = castText(hero, friend1, friend2);
  final heroName = hero.trim().isEmpty ? 'Hero' : NurseryCharacter('', hero).shortName;
  final names = <String>[
    heroName,
    if (friend1.trim().isNotEmpty) NurseryCharacter('', friend1).shortName,
    if (friend2.trim().isNotEmpty) NurseryCharacter('', friend2).shortName,
  ].join(', ');
  var shortTopic = _clean(topic);
  if (shortTopic.length > 60) shortTopic = '${shortTopic.substring(0, 60).trim()}…';
  String fill(String t) => t.replaceAll('{cast}', names).replaceAll('{hero}', heroName).replaceAll('{topic}', shortTopic.isEmpty ? 'a happy song' : shortTopic);
  final out = <NurseryPackScene>[];
  final pick = arcPick(n);
  for (var i = 0; i < n; i++) {
    final beat = nurseryArc[pick[i]];
    final action = fill(beat.action);
    final line = i < lyricScenes.length && lyricScenes[i].lines.isNotEmpty ? lyricScenes[i].text : fill(beat.line);
    final who = beat.heroOnly ? hero : cast;
    out.add(NurseryPackScene(
      number: i + 1,
      action: action,
      line: line,
      imagePrompt: 'Scene ${i + 1}: ${_clean(who)}, $action, world of $shortTopic. ${style.english}, soft rim lighting. '
          'Use the attached character sheet and keep the same faces, colors and clothes. Aspect ratio $ratio. '
          'No text, no letters, no watermark, no scary elements, no real people, no existing cartoon characters or logos.',
      videoPrompt: '${beat.camera}. Smooth 24fps toddler animation for $videoTool, consistent character outfits, '
          'keep the attached picture as the first frame. No new characters, no text, no morphing faces, no sudden cuts, nothing scary.',
    ));
  }
  return out;
}

/// One picture prompt for a character sheet (a reference picture the person makes once and reuses in every scene).
class NurseryCastSheet {
  const NurseryCastSheet({required this.role, required this.name, required this.prompt});

  final String role;
  final String name;
  final String prompt;
}

/// A sheet for the hero, one for each friend and, with two or more characters, a height-comparison lineup
/// (the v3 notebook's cast sheets). Empty friends are skipped.
List<NurseryCastSheet> buildCastSheets({required String hero, String friend1 = '', String friend2 = '', NurseryStyle style = NurseryStyle.cartoon3d}) {
  final out = <NurseryCastSheet>[];
  final cast = <String>[];
  void add(String role, String desc) {
    final d = _clean(desc);
    if (d.isEmpty) return;
    cast.add(d);
    out.add(NurseryCastSheet(role: role, name: NurseryCharacter('', d).shortName, prompt: buildCharacterPrompt(character: d, style: style)));
  }

  add('Hero', hero);
  add('Friend 1', friend1);
  add('Friend 2', friend2);
  if (cast.length > 1) {
    out.add(NurseryCastSheet(
      role: 'Group lineup',
      name: 'All ${cast.length} characters',
      prompt: 'Full-body height comparison lineup of ORIGINAL children\'s cartoon characters: ${cast.join(' standing side-by-side with ')}. '
          'Smiling forward on a clean studio backdrop, consistent scale. ${style.english}. '
          'Do not copy any existing cartoon character, brand or logo. No text, no letters, no watermark.',
    ));
  }
  return out;
}

/// Words to put in the "negative prompt" box of an image or video AI that has one.
const nurseryNegativePrompt = 'scary, dark shadows, creepy eyes, distorted hands, extra fingers, text, letters, watermark, blurry, violence, realistic people, existing cartoon characters, logos';

/// Title and tag ideas for the upload. Plain text, no claims about views or earnings.
class NurserySeo {
  const NurserySeo({required this.titles, required this.tags, this.description = '', this.thumbs = const []});

  final List<String> titles;
  final String tags;
  final String description;
  final List<NurseryThumb> thumbs;
}

/// A thumbnail idea: the picture prompt (no text in the picture) and the words to add afterwards in an editor.
class NurseryThumb {
  const NurseryThumb({required this.concept, required this.overlay, required this.prompt});

  final String concept;
  final String overlay;
  final String prompt;
}

NurserySeo buildSeo({required String topic, required String hero, String cast = '', NurseryStyle style = NurseryStyle.cartoon3d}) {
  final t = _clean(topic);
  final short = t.length > 45 ? '${t.substring(0, 45).trim()}…' : t;
  final short40 = t.length > 40 ? '${t.substring(0, 40).trim()}…' : t;
  final h = hero.trim().isEmpty ? 'Friends' : NurseryCharacter('', hero).shortName;
  final who = _clean(cast).isEmpty ? _clean(hero) : _clean(cast);
  final subject = who.isEmpty ? 'a cute original cartoon character' : who;
  String thumb(String scene) =>
      'YouTube kids thumbnail, 16:9. $scene. ${style.english}, bright sunburst background, one clear focal point, readable at small size, '
      'an empty area kept free for a title added later. No text, no letters, no watermark, no existing cartoon characters or logos.';
  return NurserySeo(
    titles: [
      '${short.isEmpty ? 'Sing Along' : short} | Nursery Rhymes & Kids Songs | $h',
      'Clap & Sing Along! 🎵 ${short40.isEmpty ? 'Kids Song' : short40} | Toddler Animation',
      'Kids Songs: ${short.isEmpty ? 'Sing Along' : short} | Cute Cartoon Animation',
    ],
    tags: 'nursery rhymes, kids songs, toddler learning, ${h.toLowerCase()}, sing along, kids animation',
    description: 'Sing, dance, and learn with $h and friends!\n\nIn this episode: ${t.isEmpty ? 'a happy sing-along' : t}\n\n'
        'The song and the pictures were made with AI tools.\n\n#NurseryRhymes #KidsSongs #ToddlerLearning #KidsAnimation',
    thumbs: [
      NurseryThumb(concept: 'Big happy close-up', overlay: 'SING & DANCE! 🎵', prompt: thumb('Joyful close-up of $subject with floating musical notes')),
      NurseryThumb(concept: 'The whole cast celebrating', overlay: 'SING ALONG ⭐', prompt: thumb('$subject jumping in celebration with balloons and confetti')),
      NurseryThumb(concept: 'Curious discovery', overlay: '1, 2, 3 GO! 🌈', prompt: thumb('$subject pointing excitedly at a glowing rainbow treasure box')),
    ],
  );
}

/// Weights for the time of each scene when the backend shares the song over the lyrics by line length (the same rule as its
/// "lyrics" karaoke: each line counts its characters, at least 4), so a scene changes where its first line starts.
List<double> sceneWeights(List<NurseryScene> scenes) =>
    [for (final s in scenes) s.lines.isEmpty ? 4.0 : s.lines.fold<double>(0, (a, l) => a + (l.length < 4 ? 4 : l.length))];

/// What the Nursery screen remembers between visits (on this phone only). Indexes are into the enums / library lists
/// and are clamped when read, so an old or damaged save can never break the screen.
class NurseryDraft {
  const NurseryDraft({
    this.topic = '',
    this.theme = 0,
    this.hero = 0,
    this.friend1 = -1,
    this.friend2 = -1,
    this.heroCustom = '',
    this.lang = 0,
    this.style = 0,
    this.tempo = 0,
    this.tool = 0,
    this.ratio = '16:9',
    this.scenes = 6,
    this.lyrics = '',
    this.sceneFiles = const {},
    this.song = '',
    this.songMs = 0,
    this.karaoke = '',
    this.genre = 0,
    this.songStyle = '',
  });

  final String topic;
  final int theme;
  final int hero; // index into nurseryCharacters; -1 = the custom text
  final int friend1; // -1 = none
  final int friend2;
  final String heroCustom;
  final int lang;
  final int style;
  final int tempo;
  final int tool;
  final String ratio;
  final int scenes;
  final String lyrics;
  final Map<int, String> sceneFiles; // scene number (1-based) -> a file name in the backend's library
  final String song; // the song's file name in the backend's library
  final int songMs;
  final String karaoke; // the .ass written by the karaoke step
  final int genre; // index into NurseryGenre.values
  final String songStyle; // the style text an AI wrote for the song AI ('' = use the generated one)

  NurseryDraft copyWith({
    String? topic,
    int? theme,
    int? hero,
    int? friend1,
    int? friend2,
    String? heroCustom,
    int? lang,
    int? style,
    int? tempo,
    int? tool,
    String? ratio,
    int? scenes,
    String? lyrics,
    Map<int, String>? sceneFiles,
    String? song,
    int? songMs,
    String? karaoke,
    int? genre,
    String? songStyle,
  }) =>
      NurseryDraft(
        topic: topic ?? this.topic,
        theme: theme ?? this.theme,
        hero: hero ?? this.hero,
        friend1: friend1 ?? this.friend1,
        friend2: friend2 ?? this.friend2,
        heroCustom: heroCustom ?? this.heroCustom,
        lang: lang ?? this.lang,
        style: style ?? this.style,
        tempo: tempo ?? this.tempo,
        tool: tool ?? this.tool,
        ratio: ratio ?? this.ratio,
        scenes: scenes ?? this.scenes,
        lyrics: lyrics ?? this.lyrics,
        sceneFiles: sceneFiles ?? this.sceneFiles,
        song: song ?? this.song,
        songMs: songMs ?? this.songMs,
        karaoke: karaoke ?? this.karaoke,
        genre: genre ?? this.genre,
        songStyle: songStyle ?? this.songStyle,
      );

  String encode() => jsonEncode({
        'topic': topic,
        'theme': theme,
        'hero': hero,
        'f1': friend1,
        'f2': friend2,
        'heroCustom': heroCustom,
        'lang': lang,
        'style': style,
        'tempo': tempo,
        'tool': tool,
        'ratio': ratio,
        'scenes': scenes,
        'lyrics': lyrics,
        'files': {for (final e in sceneFiles.entries) '${e.key}': e.value},
        'song': song,
        'songMs': songMs,
        'karaoke': karaoke,
        'genre': genre,
        'songStyle': songStyle,
      });

  static NurseryDraft decode(String? text) {
    if (text == null || text.trim().isEmpty) return const NurseryDraft();
    try {
      final m = jsonDecode(text);
      if (m is! Map) return const NurseryDraft();
      int i(String k, int d, int lo, int hi) {
        final v = m[k];
        return v is num ? v.toInt().clamp(lo, hi).toInt() : d;
      }

      String t(String k, String d) => m[k] is String ? m[k] as String : d;
      final files = <int, String>{};
      final raw = m['files'];
      if (raw is Map) {
        raw.forEach((k, v) {
          final n = int.tryParse('$k');
          if (n != null && n >= 1 && n <= 40 && v is String && v.isNotEmpty) files[n] = v;
        });
      }
      final ratio = t('ratio', '16:9');
      return NurseryDraft(
        topic: t('topic', ''),
        theme: i('theme', 0, 0, NurseryTheme.values.length - 1),
        hero: i('hero', 0, -1, nurseryCharacters.length - 1),
        friend1: i('f1', -1, -1, nurseryCharacters.length - 1),
        friend2: i('f2', -1, -1, nurseryCharacters.length - 1),
        heroCustom: t('heroCustom', ''),
        lang: i('lang', 0, 0, NurseryLang.values.length - 1),
        style: i('style', 0, 0, NurseryStyle.values.length - 1),
        tempo: i('tempo', 0, 0, nurseryTempos.length - 1),
        tool: i('tool', 0, 0, nurseryVideoTools.length - 1),
        ratio: ratio == '9:16' ? '9:16' : '16:9',
        scenes: i('scenes', 6, 4, 12),
        lyrics: t('lyrics', ''),
        sceneFiles: files,
        song: t('song', ''),
        songMs: i('songMs', 0, 0, 24 * 3600 * 1000),
        karaoke: t('karaoke', ''),
        genre: i('genre', 0, 0, NurseryGenre.values.length - 1),
        songStyle: t('songStyle', ''),
      );
    } catch (_) {
      return const NurseryDraft();
    }
  }
}

/// The steps to check before putting a children's song video on YouTube.
const nurseryChecklist = <String>[
  '"Made for kids" ကို YouTube Studio မှာ ရွေးပါ (ကလေးအတွက် ဗီဒီယိုဆိုရင် မဖြစ်မနေ လိုတယ်)။ ဒါဆိုရင် comment နဲ့ အချို့ feature တွေ ပိတ်သွားမယ်၊ ကြော်ငြာလည်း ပြောင်းလဲမယ်။',
  'AI နဲ့ ဖန်တီးထားတယ်ဆိုတာ ဖော်ပြပါ (YouTube Studio ရဲ့ "altered or synthetic content" မေးခွန်းကို မှန်မှန်ဖြေပါ)။',
  'သီချင်း၊ သံစဉ်၊ ပုံက ကိုယ့်ဟာကိုယ် ဖန်တီးတာ ဖြစ်ရမယ်။ ရှိပြီးသား သီချင်း၊ cartoon ဇာတ်ကောင်၊ brand ကို မတုပါနဲ့ (prompt ထဲ မပါအောင် ပြောထားပြီး)။',
  'သီချင်းကို Suno စတဲ့ AI tool နဲ့ ထုတ်ရင် ကိုယ့် plan ရဲ့ သုံးခွင့် (commercial / YouTube monetization) ကို အဲဒီ tool ရဲ့ စည်းကမ်းမှာ ကိုယ်တိုင်စစ်ပါ။ Free plan က တင်ခွင့်မပေးတာ ရှိတယ်။',
  'ကလေးအတွက် မသင့်တဲ့ အရာ (ကြောက်စရာ၊ အကြမ်းဖက်၊ အန္တရာယ်ရှိတဲ့ အပြုအမူ) မပါဘူးဆိုတာ ကြည့်ပါ။',
  'ခေါင်းစဉ်/ဖော်ပြချက်မှာ ဘာသာစကား၊ အသက်အရွယ်၊ "nursery rhyme / kids song" ပါအောင် ရေးပါ၊ ကလေးကို လှည့်စားတဲ့ title မထားပါနဲ့။',
  'ဗီဒီယိုလွှတ်ခါစမှာ ပုံ/အသံ အမှား (လက်ချောင်း၊ စာလုံးပါနေတာ၊ အသံပျက်) ရှိမရှိ အစအဆုံး တစ်ခါကြည့်ပါ။',
  'ဒီ app က သင့်လျော်မှု၊ မူပိုင်ခွင့်၊ monetization ရမယ်ဆိုတာ အာမမခံပါ။ YouTube ရဲ့ လက်ရှိ စည်းကမ်းကို ကိုယ်တိုင်ဖတ်ပါ။',
];
