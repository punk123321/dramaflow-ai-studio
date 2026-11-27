import 'package:aistudio/core/thumbnail_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default prompt is a 16:9 xianxia thumbnail with no text and original characters', () {
    final p = buildThumbnailPrompt();
    expect(p, contains('16:9'));
    expect(p, contains('xianxia'));
    expect(p, contains('ORIGINAL'));
    expect(p, contains('No text'));
    expect(p, contains('left third'));
  });

  test('the given character, scene, title and mood are used', () {
    final p = buildThumbnailPrompt(title: 'Sword Immortal', character: 'a  silver-haired\nmaster', scene: 'on a cliff', mood: ThumbMood.romance);
    expect(p, contains('Sword Immortal'));
    expect(p, contains('a silver-haired master'));
    expect(p, contains('Scene: on a cliff.'));
    expect(p, contains(ThumbMood.romance.english));
    expect(p, isNot(contains('original young cultivator')));
  });

  test('empty scene adds no scene line, and no text-space option centres the subject', () {
    final p = buildThumbnailPrompt(leaveTextSpace: false);
    expect(p, isNot(contains('Scene:')));
    expect(p, contains('center third'));
    expect(p, isNot(contains('left third')));
  });

  test('a reference image line is added only when asked, and it keeps the character original', () {
    expect(buildThumbnailPrompt(), isNot(contains('Reference image')));
    final p = buildThumbnailPrompt(referenceImage: true);
    expect(p, contains('Reference image'));
    expect(p, contains('ONLY as a guide'));
    expect(p, contains('Do NOT copy its faces'));
    expect(p, contains('If no image is attached, ignore'));
    expect(p, contains('invent an ORIGINAL character'));
  });

  test('every mood has a label and an English phrase', () {
    for (final m in ThumbMood.values) {
      expect(m.label.isNotEmpty, isTrue);
      expect(m.english.isNotEmpty, isTrue);
    }
  });
}
