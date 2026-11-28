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
    test('the character library has 16 characters with short names', () {
      expect(nurseryCharacters.length, 16);
      expect(nurseryCharacters[0].shortName, 'Mimi');
      expect(nurseryCharacters[13].shortName, 'Shwe Sin');
      expect(const NurseryCharacter('x', '').shortName, 'Hero');
      for (final c in nurseryCharacters) {
        expect(c.desc.length, greaterThan(20));
        expect(c.desc.toLowerCase(), isNot(contains('cocomelon')));
      }
    });

    test('presets point at real characters', () {
      expect(nurseryPresets.length, 3);
      for (final p in nurseryPresets) {
        for (final i in [p.hero, p.friend1, p.friend2]) {
          if (i != null) expect(i, inInclusiveRange(0, nurseryCharacters.length - 1));
        }
      }
      expect(nurseryPresets[2].lang, NurseryLang.burmese);
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

    test('buildPackScenes: count 4..9, hero-only shots, lyrics become the lines, topic is shortened', () {
      final hero = nurseryCharacters[0].desc;
      final f1 = nurseryCharacters[4].desc;
      final scenes = buildPackScenes(topic: 'x' * 100, hero: hero, friend1: f1, count: 99, ratio: '9:16', videoTool: 'Runway');
      expect(scenes.length, 9);
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

    test('the arc repeats after 9 scenes and scene prompts never name a brand', () {
      expect(nurseryArc.length, 9);
      final all = buildPackScenes(topic: 't', hero: nurseryCharacters[0].desc, count: 9).map((e) => '${e.imagePrompt} ${e.videoPrompt}').join(' ').toLowerCase();
      expect(all, isNot(contains('cocomelon')));
    });

    test('seo gives two titles and tags with the hero name', () {
      final seo = buildSeo(topic: 'Brush your teeth', hero: nurseryCharacters[0].desc);
      expect(seo.titles.length, 2);
      expect(seo.titles.first, contains('Mimi'));
      expect(seo.tags, contains('mimi'));
      expect(buildSeo(topic: '', hero: '').titles.first, contains('Friends'));
    });
  });
}
