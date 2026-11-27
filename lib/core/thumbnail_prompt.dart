/// The feeling of the picture. Each has the English words an image model understands.
enum ThumbMood {
  battle('တိုက်ပွဲ / ပြင်းထန်', 'an epic duel moment, shockwaves of qi, flying swords mid-air, intense and heroic'),
  romance('ချစ်ကြည်နူး', 'a tender, romantic moment between two cultivators, soft glow, drifting petals, longing eyes'),
  mystery('လျှို့ဝှက် / မှော်', 'a mysterious ancient secret, eerie mist, glowing runes, ominous and curious'),
  revenge('ကလဲ့စား / ပြန်လည်မွေးဖွား', 'a cold, determined reborn hero ready for revenge, dramatic backlight, fierce calm gaze');

  const ThumbMood(this.label, this.english);

  final String label;
  final String english;
}

/// An image-model prompt for a YouTube thumbnail of a Chinese AI-made xianxia
/// (cultivation / immortal fantasy) drama recap. The prompt is in English because
/// image models follow it better. It asks for ORIGINAL characters only: no real
/// actor's face, no character or poster of an existing show, no logo. Text is
/// left out of the picture on purpose (image models spell badly and cannot do
/// Burmese); the title is added afterwards, so the prompt reserves empty space.
/// With [referenceImage] the person attaches a sample picture next to the prompt: it is used only for
/// the look (layout, colours, lighting, mood), never for the faces, characters, logos or text in it.
String buildThumbnailPrompt({
  String title = '',
  String character = '',
  String scene = '',
  ThumbMood mood = ThumbMood.battle,
  bool leaveTextSpace = true,
  bool referenceImage = false,
}) {
  String clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
  final who = clean(character);
  final what = clean(scene);
  final name = clean(title);
  final b = StringBuffer();
  b.writeln('Create a YouTube thumbnail image, 16:9 landscape (1280x720), for a Chinese xianxia cultivation fantasy drama recap.');
  if (name.isNotEmpty) b.writeln('Drama theme (for mood only, do not write it in the picture): $name.');
  b.writeln('Mood: ${mood.english}.');
  b.writeln('Main character: ${who.isEmpty ? 'an original young cultivator in flowing white and jade-green hanfu robes, long black hair with a jade hairpin, sharp expressive eyes' : who}. Show the face large, in a dramatic close-up or medium shot, strong emotion.');
  if (what.isNotEmpty) b.writeln('Scene: $what.');
  b.writeln('Setting and style: floating misty mountains, ancient pagodas above the clouds, glowing golden and cyan spiritual qi, flying swords, drifting petals and light particles; cinematic lighting with a bright rim light, deep contrast, rich saturated colors (gold, jade, azure), highly detailed, painterly semi-realistic donghua look.');
  b.writeln('Composition: one clear focal point, subject on the ${leaveTextSpace ? 'right' : 'center'} third, a darker or softer ${leaveTextSpace ? 'empty area on the left third kept free for a title added later, ' : ''}clean readable at small size.');
  if (referenceImage) {
    b.writeln('Reference image: a sample picture is attached. Use it ONLY as a guide for the overall look: composition, colour palette, lighting, contrast and mood. Do NOT copy its faces, characters, costumes, logos, watermarks or any text; the character and scene must still be ORIGINAL and follow the description above. If no image is attached, ignore this line.');
  }
  b.writeln('Rules: invent an ORIGINAL character. Do not copy any real actor, celebrity, existing drama or anime character, poster, or logo. No text, no letters, no watermark, no subtitles, no borders. No extra fingers or distorted hands.');
  return b.toString().trim();
}
