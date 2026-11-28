import 'package:aistudio/core/nursery.dart';
import 'package:aistudio/core/nursery_pack.dart';
import 'package:flutter_test/flutter_test.dart';

NurseryPackInput input({int scenes = 6, NurseryLang lang = NurseryLang.english, String topic = 'Farm friends singing a song'}) => NurseryPackInput(
      topic: topic,
      hero: characterDesc('🐶 Barnaby — Golden Puppy'),
      friend1: characterDesc('🦆 Ducky — Yellow Duckling'),
      friend2: '',
      lang: lang,
      scenes: scenes,
      bpm: 118,
    );

void main() {
  test('the cast has 16 characters with unique keys, each looked up by its key', () {
    expect(nurseryCharacters.length, 16);
    expect({for (final c in nurseryCharacters) c.key}.length, 16);
    for (final c in nurseryCharacters) {
      expect(characterDesc(c.key), c.desc);
      expect(shortName(c.desc).isNotEmpty, isTrue);
    }
    expect(characterDesc('nobody'), '');
    expect(shortName('Mimi, a cheerful girl'), 'Mimi');
    expect(shortName(''), '');
  });

  test('presets point at real characters and real tempos', () {
    for (final p in nurseryPresets) {
      expect(characterDesc(p.hero), isNotEmpty, reason: p.label);
      expect(characterDesc(p.friend1), isNotEmpty, reason: p.label);
      expect(characterDesc(p.friend2), isNotEmpty, reason: p.label);
      expect(p.scenes, inInclusiveRange(4, 9));
      expect(nurseryVideoTools, contains(p.tool));
    }
  });

  test('a pack has the asked number of scenes (4..9), numbered and timed one after the other', () {
    expect(buildPack(input(scenes: 6)).scenes.length, 6);
    expect(buildPack(input(scenes: 1)).scenes.length, 4);
    expect(buildPack(input(scenes: 40)).scenes.length, 9);
    final s = buildPack(input(scenes: 5)).scenes;
    for (var i = 0; i < s.length; i++) {
      expect(s[i].num, i + 1);
      expect(s[i].startSec, i * 8);
      expect(s[i].endSec, (i + 1) * 8);
    }
    expect(s[1].timestamp, '00:08 - 00:16');
    expect(s[0].action, contains('Barnaby'));
  });

  test('every prompt is safe: no text, no brands, original characters only', () {
    final pack = buildPack(input());
    final all = [pack.musicPrompt, pack.characterPrompt, for (final s in pack.scenes) ...[s.imagePrompt, s.videoPrompt]].join('\n');
    expect(all.toLowerCase(), isNot(contains('cocomelon')));
    expect(all.toLowerCase(), isNot(contains('pixar')));
    for (final s in pack.scenes) {
      expect(s.imagePrompt, contains('No text'));
      expect(s.imagePrompt, contains('attached character sheet'));
      expect(s.imagePrompt, contains('16:9'));
      expect(s.videoPrompt, contains('No new characters'));
      expect(s.videoPrompt, contains('attached picture'));
    }
    expect(pack.characterPrompt, contains('ORIGINAL'));
  });

  test('the hero-only scenes use the hero, the others use the whole cast', () {
    final s = buildPack(input()).scenes;
    expect(s[0].imagePrompt, contains('Barnaby, a cute chubby baby golden retriever'));
    expect(s[0].imagePrompt, isNot(contains('Ducky, a cheerful')));
    expect(s[1].imagePrompt, contains('alongside Ducky, a cheerful'));
  });

  test('the lyrics skeleton has sections, never pastes the topic sentence, and follows the language', () {
    const topic = 'a very long topic sentence about animals that must not be sung';
    for (final l in NurseryLang.values) {
      final p = buildPack(input(lang: l, topic: topic));
      expect(p.lyrics, contains('[Chorus]'), reason: '$l');
      expect(p.lyrics, isNot(contains('long topic sentence')), reason: '$l');
      expect(p.lyrics, contains('Barnaby'), reason: '$l');
    }
    expect(buildPack(input(lang: NurseryLang.burmese)).lyrics, contains('လင်းလက်'));
    expect(buildPack(input(lang: NurseryLang.chinese)).lyrics, contains('拍拍手'));
    expect(buildPack(input(lang: NurseryLang.bilingual)).lyrics, contains('Clap your hands'));
  });

  test('the lyrics skeleton can be read back as scenes', () {
    final scenes = splitScenes(buildPack(input()).lyrics);
    expect(scenes.map((e) => e.label).toList(), ['Intro', 'Verse 1', 'Chorus', 'Outro']);
  });

  test('titles are cut at a word and tags carry the hero name', () {
    final p = buildPack(input(topic: 'Farm animal friends forming a joyful musical band in the sunny meadow, singing together'));
    expect(p.titles.length, 2);
    expect(p.titles[0].startsWith('Farm animal friends forming a joyful'), isTrue);
    expect(p.titles[0], contains('| Barnaby'));
    expect(p.tags, contains('barnaby'));
    expect(cutText('abcdef ghij', 8), 'abcdef');
    expect(cutText('short', 8), 'short');
    expect(cutText('abcdefghijkl', 5), 'abcde');
  });

  test('the same choices give the same pack', () {
    final a = buildPack(input());
    final b = buildPack(input());
    expect(a.scenes.map((e) => e.imagePrompt).toList(), b.scenes.map((e) => e.imagePrompt).toList());
    expect(a.lyrics, b.lyrics);
  });

  test('remix changes only the asked scene, is repeatable and takes a note', () {
    final x = input();
    final pack = buildPack(x);
    final r0 = remixScene(pack.scenes[2], x, pick: 0);
    final r0b = remixScene(pack.scenes[2], x, pick: 0);
    final r1 = remixScene(pack.scenes[2], x, pick: 1);
    expect(r0.num, 3);
    expect(r0.startSec, pack.scenes[2].startSec);
    expect(r0.action, contains('rainbow'));
    expect(r0.imagePrompt, r0b.imagePrompt);
    expect(r1.action, isNot(r0.action));
    expect(remixScene(pack.scenes[2], x, note: 'riding a kite').action, 'riding a kite');
    expect(r0.imagePrompt, contains('No text'));
    expect(r0.videoPrompt, contains('Crane-up'));
  });
}
