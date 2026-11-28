import 'package:aistudio/core/nursery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lyrics prompt asks for original lyrics in a fixed format', () {
    final p = buildLyricsPrompt(theme: NurseryTheme.numbers, lang: NurseryLang.burmese, verses: 2, character: 'Mimi the bunny');
    expect(p, contains('ORIGINAL'));
    expect(p, contains('counting from one to ten'));
    expect(p, contains('Burmese'));
    expect(p, contains('2 verses'));
    expect(p, contains('Mimi the bunny'));
    expect(p, contains('[Verse 1]'));
    expect(p, contains('do not copy'));
  });

  test('custom theme uses the text; verses are limited to 1..8', () {
    expect(buildLyricsPrompt(theme: NurseryTheme.custom, custom: 'a sleepy moon'), contains('a sleepy moon'));
    expect(buildLyricsPrompt(verses: 99), contains('8 verses'));
    expect(buildLyricsPrompt(verses: 0), contains('1 verses'));
  });

  test('music prompt has no artist names and asks for an original melody', () {
    final p = buildMusicPrompt(bpm: 90, female: false);
    expect(p, contains('90 BPM'));
    expect(p, contains('male'));
    expect(p, contains('Original melody'));
    expect(p, contains('Do not imitate'));
  });

  test('character and scene prompts keep the character and ban text and existing characters', () {
    final c = buildCharacterPrompt(character: 'a red fox cub');
    expect(c, contains('a red fox cub'));
    expect(c, contains('ORIGINAL'));
    expect(c, contains('No text'));
    final s = buildScenePrompt(sceneText: 'The fox  hops\nhigh', character: 'a red fox cub', ratio: '9:16');
    expect(s, contains('"The fox hops high"'));
    expect(s, contains('9:16'));
    expect(s, contains('attached character sheet'));
    expect(s, contains('no existing cartoon characters'));
    expect(buildScenePrompt(sceneText: 'x', hasReferenceImage: false), isNot(contains('attached')));
  });

  test('video prompt animates the attached picture, rotates the camera move and bans new things', () {
    final a = buildVideoPrompt(sceneText: 'The fox  hops', index: 0, character: 'a red fox cub', seconds: 4);
    expect(a, contains('4-second'));
    expect(a, contains('"The fox hops"'));
    expect(a, contains('attached picture'));
    expect(a, contains(nurseryMoves[0]));
    expect(a, contains('a red fox cub'));
    expect(a, contains('No new characters'));
    expect(buildVideoPrompt(sceneText: 'x', index: 1), contains(nurseryMoves[1]));
    expect(buildVideoPrompt(sceneText: 'x', index: nurseryMoves.length), contains(nurseryMoves[0]));
    expect(buildVideoPrompt(sceneText: 'x', index: -1), contains(nurseryMoves[1]));
  });

  test('splitScenes: headings become labels, blank lines split, markdown is removed', () {
    const text = '''
**[Verse 1]**
Little bunny hops along
Singing a happy song

[Chorus]
La la la, hop hop hop
La la la, never stop

Second part without heading
one more line
''';
    final s = splitScenes(text);
    expect(s.length, 3);
    expect(s[0].label, 'Verse 1');
    expect(s[0].lines, ['Little bunny hops along', 'Singing a happy song']);
    expect(s[1].label, 'Chorus');
    expect(s[2].label, 'Scene 3');
    expect(s[2].lines.length, 2);
    expect(s[0].text, 'Little bunny hops along / Singing a happy song');
  });

  test('splitScenes: Chinese brackets, empty text and the scene limit', () {
    expect(splitScenes('【第一段】\n小兔子跳跳').first.label, '第一段');
    expect(splitScenes('   \n\n'), isEmpty);
    final many = List.generate(10, (i) => 'line $i').join('\n\n');
    final cut = splitScenes(many, maxScenes: 4);
    expect(cut.length, 4);
    expect(cut.last.lines.length, 7); // no lyric line is lost
    expect(cut.expand((e) => e.lines).length, 10);
  });

  test('equalTimes shares the song by lines, sums to the song length and respects the minimum', () {
    final scenes = [
      const NurseryScene(label: 'a', lines: ['1', '2', '3', '4']),
      const NurseryScene(label: 'b', lines: ['1', '2']),
    ];
    final t = equalTimes(scenes, 60);
    expect(t.length, 2);
    expect(t[0], closeTo(40, 0.001));
    expect(t[1], closeTo(20, 0.001));
    expect(t.fold<double>(0, (a, b) => a + b), closeTo(60, 0.001));
    final skew = [
      const NurseryScene(label: 'a', lines: ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16', '17', '18', '19']),
      const NurseryScene(label: 'b', lines: ['1']),
    ];
    final k = equalTimes(skew, 20, minSec: 2);
    expect(k[1], greaterThanOrEqualTo(2 - 1e-9));
    expect(k.fold<double>(0, (a, b) => a + b), closeTo(20, 0.001));
    expect(equalTimes(const [], 10), isEmpty);
    expect(equalTimes(scenes, 0), isEmpty);
  });

  test('the checklist covers made-for-kids, AI disclosure and music licence', () {
    final all = nurseryChecklist.join('\n');
    expect(all, contains('Made for kids'));
    expect(all, contains('AI'));
    expect(all, contains('Suno'));
  });

  group('ported from the KidsTube starter', () {
    test('the character library has 26 characters with short names', () {
      expect(nurseryCharacters.length, 26);
      expect(nurseryCharacters[0].shortName, 'Mimi');
      expect(nurseryCharacters[13].shortName, 'Shwe Sin');
      expect(nurseryCharacters[16].shortName, 'Maya and Max');
      expect(nurseryCharacters[23].shortName, 'Nimbus');
      expect(nurseryCharacters[25].shortName, isNotEmpty);
      expect(const NurseryCharacter('x', '').shortName, 'Hero');
      for (final c in nurseryCharacters) {
        expect(c.desc.length, greaterThan(20));
        expect(c.desc.toLowerCase(), isNot(contains('cocomelon')));
      }
    });

    test('presets point at real characters', () {
      expect(nurseryPresets.length, 5);
      for (final p in nurseryPresets) {
        for (final i in [p.hero, p.friend1, p.friend2]) {
          if (i != null) expect(i, inInclusiveRange(0, nurseryCharacters.length - 1));
        }
      }
      expect(nurseryPresets[2].lang, NurseryLang.burmese);
      expect(nurseryPresets[3].style, NurseryStyle.clay);
      expect(nurseryPresets[4].lang, NurseryLang.bilingual);
      for (final p in nurseryPresets) {
        expect(nurseryTempos, contains(p.tempo));
        expect(nurseryVideoTools, contains(p.videoTool));
      }
    });

    test('no style text names an existing brand', () {
      for (final st in NurseryStyle.values) {
        expect(st.english.toLowerCase(), isNot(contains('cocomelon')));
        expect(st.english.toLowerCase(), isNot(contains('pixar')));
      }
    });

    test('bpmOf reads the number and falls back', () {
      expect(bpmOf('Upbeat & Bouncy (118 BPM)'), 118);
      expect(bpmOf('Lullaby (72 bpm)'), 72);
      expect(bpmOf('no number'), 115);
      expect(bpmOf('x (999 BPM)', fallback: 100), 100);
    });

    test('castText joins hero and friends and skips empty ones', () {
      expect(castText('A'), 'A');
      expect(castText('A', 'B'), 'A alongside B');
      expect(castText('A', 'B', 'C'), 'A alongside B and C');
      expect(castText('A', '', 'C'), 'A and C');
    });

    test('buildPackScenes: count 4..12, hero-only shots, lyrics become the lines, topic is shortened', () {
      final hero = nurseryCharacters[0].desc;
      final f1 = nurseryCharacters[4].desc;
      final scenes = buildPackScenes(topic: 'x' * 100, hero: hero, friend1: f1, count: 99, ratio: '9:16', videoTool: 'Runway');
      expect(scenes.length, 12);
      expect(scenes.first.number, 1);
      expect(scenes.first.action, contains('Mimi waving'));
      expect(scenes.first.imagePrompt, contains(hero));
      expect(scenes[1].imagePrompt, contains('alongside'));
      expect(scenes.first.imagePrompt, isNot(contains('alongside'))); // hero-only shot
      expect(scenes[2].action, contains('…'));
      expect(scenes.first.imagePrompt, contains('9:16'));
      expect(scenes.first.imagePrompt, contains('No text'));
      expect(scenes.first.videoPrompt, contains('Runway'));
      expect(scenes.first.videoPrompt, contains('No new characters'));
      expect(buildPackScenes(topic: 't', hero: hero, count: 1).length, 4);
      final lyr = buildPackScenes(topic: 't', hero: hero, count: 4, lyricScenes: const [
        NurseryScene(label: 'v', lines: ['la la', 'hop hop']),
      ]);
      expect(lyr[0].line, 'la la / hop hop');
      expect(lyr[1].line, contains('Look who is here')); // no lyric for this one: the arc's line
    });

    test('the arc has 12 beats and scene prompts never name a brand', () {
      expect(nurseryArc.length, 12);
      final all = buildPackScenes(topic: 't', hero: nurseryCharacters[0].desc, count: 12).map((e) => '${e.imagePrompt} ${e.videoPrompt}').join(' ').toLowerCase();
      expect(all, isNot(contains('cocomelon')));
    });

    test('seo gives three titles, a description and tags with the hero name', () {
      final seo = buildSeo(topic: 'Brush your teeth', hero: nurseryCharacters[0].desc);
      expect(seo.titles.length, 3);
      expect(seo.description, contains('made with AI'));
      expect(seo.description, contains('Brush your teeth'));
      expect(seo.titles.first, contains('Mimi'));
      expect(seo.tags, contains('mimi'));
      expect(buildSeo(topic: '', hero: '').titles.first, contains('Friends'));
    });
  });

  group('draft and weights', () {
    test('sceneWeights count the characters of the lines, at least 4 each', () {
      const sc = [
        NurseryScene(label: 'a', lines: ['abcdefghij', 'ab']),
        NurseryScene(label: 'b', lines: []),
      ];
      expect(sceneWeights(sc), [14.0, 4.0]);
    });

    test('a draft survives encode / decode', () {
      final d = const NurseryDraft().copyWith(
        topic: 'Teeth',
        hero: 3,
        friend1: 4,
        lang: 2,
        ratio: '9:16',
        scenes: 8,
        lyrics: '[Verse 1]\nla la',
        sceneFiles: {1: 'a.png', 3: 'b.mp4'},
        song: 'song.mp3',
        songMs: 61000,
        karaoke: 's_karaoke.ass',
        genre: 5,
        songStyle: 'calm 76 BPM, music box',
      );
      final r = NurseryDraft.decode(d.encode());
      expect(r.topic, 'Teeth');
      expect(r.hero, 3);
      expect(r.friend1, 4);
      expect(r.friend2, -1);
      expect(r.lang, 2);
      expect(r.ratio, '9:16');
      expect(r.scenes, 8);
      expect(r.lyrics, '[Verse 1]\nla la');
      expect(r.sceneFiles, {1: 'a.png', 3: 'b.mp4'});
      expect(r.song, 'song.mp3');
      expect(r.songMs, 61000);
      expect(r.karaoke, 's_karaoke.ass');
      expect(r.genre, 5);
      expect(r.songStyle, 'calm 76 BPM, music box');
    });

    test('a damaged or old save never breaks it: bad values are clamped or ignored', () {
      expect(NurseryDraft.decode(null).scenes, 6);
      expect(NurseryDraft.decode('').hero, 0);
      expect(NurseryDraft.decode('not json').hero, 0);
      expect(NurseryDraft.decode('[1,2]').hero, 0);
      final r = NurseryDraft.decode('{"hero":999,"f1":-50,"scenes":100,"lang":-1,"ratio":"4:3","files":{"0":"x","2":"ok.png","3":5,"99":"y"}}');
      expect(r.hero, nurseryCharacters.length - 1);
      expect(r.friend1, -1);
      expect(r.scenes, 12);
      expect(r.lang, 0);
      expect(r.genre, 0);
      expect(r.songStyle, '');
      expect(r.ratio, '16:9');
      expect(r.sceneFiles, {2: 'ok.png'});
    });

    test('lyric-driven scene counts are allowed beyond 4..9', () {
      final hero = nurseryCharacters[0].desc;
      expect(buildPackScenes(topic: 't', hero: hero, count: 14, minCount: 1, maxCount: 40).length, 14);
      expect(buildPackScenes(topic: 't', hero: hero, count: 2, minCount: 1, maxCount: 40).length, 2);
    });
  });

  group('from the v3 notebook', () {
    test('arcPick: welcome first, goodbye last, never a repeat, for every size up to 12', () {
      for (var n = 2; n <= 12; n++) {
        final p = arcPick(n);
        expect(p.length, n, reason: 'n=$n');
        expect(p.first, 0);
        expect(p.last, 11);
        expect(p.toSet().length, n, reason: 'no repeat for n=$n: $p');
        final sorted = [...p]..sort();
        expect(p, sorted);
      }
      expect(arcPick(1), [0]);
      expect(arcPick(0), isEmpty);
      expect(arcPick(14).length, 14);
      expect(arcPick(14)[12], 0); // above 12 the arc repeats
    });

    test('a 6-scene plan ends with the goodbye', () {
      final s = buildPackScenes(topic: 't', hero: nurseryCharacters[0].desc, count: 6);
      expect(s.last.action, contains('goodbye'));
      expect(s.first.action, contains('waving'));
    });

    test('genres have words and no brand names; the music prompt follows tempo and genre', () {
      expect(NurseryGenre.values.length, 8);
      for (final g in NurseryGenre.values) {
        expect(g.words.length, greaterThan(10));
        expect(g.words.toLowerCase(), isNot(contains('cocomelon')));
      }
      final calm = buildMusicPrompt(bpm: 76, genre: NurseryGenre.lullaby);
      expect(calm, contains('music box'));
      expect(calm, contains('76 BPM'));
      final fun = buildMusicPrompt(bpm: 120, genre: NurseryGenre.march);
      expect(fun, contains('ukulele'));
      expect(fun, contains('marching band'));
      expect(fun, isNot(contains('music box')));
    });

    test('the songwriter prompt asks for SUNO STYLE and LYRICS, with the twist, and names no brand', () {
      final p = buildLyricsPrompt(genre: NurseryGenre.dancePop, tempo: 'Upbeat & Bouncy (118 BPM)', twist: 'add a funny sneeze', withStyle: true, character: 'Mimi');
      expect(p, contains('SUNO STYLE:'));
      expect(p, contains('LYRICS:'));
      expect(p, contains('under 180 characters'));
      expect(p, contains('funky dance party pop'));
      expect(p, contains('118 BPM'));
      expect(p, contains('add a funny sneeze'));
      expect(p, contains('(clap hands)'));
      expect(p, contains('ORIGINAL'));
      final lower = p.toLowerCase();
      for (final bad in ['cocomelon', 'pinkfong', 'super simple']) {
        expect(lower, isNot(contains(bad)));
      }
      // without withStyle it is still the plain lyrics prompt
      expect(buildLyricsPrompt(genre: NurseryGenre.dancePop), isNot(contains('SUNO STYLE')));
    });

    test('splitSongAnswer separates the style from the lyrics in the usual shapes', () {
      const a = 'Sure! Here you go.\n\nSUNO STYLE:\nUpbeat kids pop, 118 BPM,\nukulele and claps\n\nLYRICS:\n[Intro]\nHey hey\n[Verse 1]\nLa la';
      final r = splitSongAnswer(a);
      expect(r.style, 'Upbeat kids pop, 118 BPM, ukulele and claps');
      expect(r.lyrics, startsWith('[Intro]'));
      expect(r.lyrics, contains('La la'));
      expect(r.lyrics, isNot(contains('SUNO')));
      final b = splitSongAnswer('**SUNO STYLE:** calm, 76 BPM\n\n**LYRICS:**\n```\n[Verse 1]\nSleep now\n```');
      expect(b.style, 'calm, 76 BPM');
      expect(b.lyrics, '[Verse 1]\nSleep now');
      final c = splitSongAnswer('Style: bouncy\n[Intro]\nHi\n[Verse 1]\nYo');
      expect(c.style, 'bouncy');
      expect(c.lyrics, startsWith('[Intro]'));
      final d = splitSongAnswer('just some words\nmore words');
      expect(d.style, '');
      expect(d.lyrics, 'just some words\nmore words');
      expect(splitSongAnswer('   ').lyrics, '');
      expect(splitSongAnswer('[Verse 1]\nla').style, '');
    });

    test('a cue line like (clap hands) is dropped from the lyrics, not turned into a scene', () {
      final s = splitScenes('[Verse 1]\nHop hop\n(clap hands)\nSkip skip\n\n[Chorus]\n(jump high)\nLa la');
      expect(s.length, 2);
      expect(s[0].lines, ['Hop hop', 'Skip skip']);
      expect(s[1].lines, ['La la']);
      // a translation line in Myanmar script inside brackets is kept
      final t = splitScenes('Clap your hands\n(လက်ခုပ်တီးမယ်)');
      expect(t.single.lines.length, 2);
    });

    test('cast sheets: one per character and a lineup for two or more', () {
      final one = buildCastSheets(hero: nurseryCharacters[0].desc);
      expect(one.length, 1);
      expect(one.first.name, 'Mimi');
      final three = buildCastSheets(hero: nurseryCharacters[0].desc, friend1: nurseryCharacters[4].desc, friend2: nurseryCharacters[10].desc);
      expect(three.map((e) => e.role), ['Hero', 'Friend 1', 'Friend 2', 'Group lineup']);
      expect(three.last.prompt, contains('standing side-by-side with'));
      expect(three.last.name, 'All 3 characters');
      for (final c in three) {
        expect(c.prompt, contains('No text'));
        expect(c.prompt, contains('ORIGINAL'));
      }
      expect(buildCastSheets(hero: '').length, 0);
      expect(nurseryNegativePrompt, contains('watermark'));
    });

    test('thumbnail ideas: three, no text in the picture, no brand', () {
      final seo = buildSeo(topic: 'Brush teeth', hero: nurseryCharacters[0].desc, cast: castText(nurseryCharacters[0].desc, nurseryCharacters[4].desc));
      expect(seo.thumbs.length, 3);
      for (final t in seo.thumbs) {
        expect(t.prompt, contains('No text'));
        expect(t.prompt, contains('16:9'));
        expect(t.overlay.isNotEmpty, isTrue);
        expect(t.prompt.toLowerCase(), isNot(contains('cocomelon')));
      }
      expect(seo.thumbs[1].prompt, contains('alongside'));
    });

    test('song ideas: 15, none empty', () {
      expect(nurserySongIdeas.length, 15);
      expect(nurserySongIdeas.every((e) => e.trim().length > 10), isTrue);
    });

    test('the new style has words', () {
      expect(NurseryStyle.clay.english, contains('clay'));
    });
  });
}
