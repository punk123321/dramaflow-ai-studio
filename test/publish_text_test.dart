import 'package:aistudio/core/publish_text.dart';
import 'package:aistudio/core/render_plan.dart';
import 'package:aistudio/core/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('publish text', () {
    test('prompt names the drama, asks for JSON and forbids evasion advice', () {
      final p = buildPublishPrompt(dramaTitle: 'ပန်းတိုင်', episode: 3, script: 'ဇာတ်လမ်းအကျဉ်း');
      expect(p, contains('ပန်းတိုင်'));
      expect(p, contains('episode 3'));
      expect(p, contains('"titles"'));
      expect(p, contains('copyright or platform checks'));
      expect(p, contains('ဇာတ်လမ်းအကျဉ်း'));
    });

    test('reply in a code fence is parsed, checked and shortened', () {
      final r = parsePublishReply('''
Sure!
```json
{"titles":["A","  B  b ","", 5, "C","D","E","F"],"description":"  hello  ","hashtags":["drama","##Recap","bad tag","#drama",""]}
```''')!;
      expect(r.titles, ['A', 'B b', 'C', 'D', 'E']);
      expect(r.description, 'hello');
      expect(r.hashtags, ['#drama', '#Recap', '#badtag']);
    });

    test('bare JSON works; junk and empty give null', () {
      expect(parsePublishReply('{"titles":["x"]}')!.titles, ['x']);
      expect(parsePublishReply('no json here'), isNull);
      expect(parsePublishReply('{"titles":[],"description":"","hashtags":[]}'), isNull);
      expect(parsePublishReply('{broken'), isNull);
    });

    test('thumbnail texts are parsed, deduplicated, cut and round-tripped', () {
      final r = parsePublishReply('{"titles":["x"],"thumbnailTexts":[" ဟုတ်လား ","ဟုတ်လား","", 3, "${'z' * 80}"]}')!;
      expect(r.thumbTexts.length, 2);
      expect(r.thumbTexts[1].length, maxThumbChars);
      expect(PublishText.decode(r.encode()).thumbTexts, r.thumbTexts);
      expect(buildPublishPrompt(dramaTitle: 'a', episode: 1, script: ''), contains('thumbnailTexts'));
      expect(parsePublishReply('{"thumbnailTexts":["only this"]}')!.thumbTexts, ['only this']);
    });

    test('long values are cut', () {
      final r = parsePublishReply('{"titles":["${'x' * 300}"],"description":"${'y' * 5000}"}')!;
      expect(r.titles.first.length, maxTitleChars);
      expect(r.description.length, maxDescriptionChars);
    });

    test('encode / decode round trip and bad input', () {
      const t = PublishText(titles: ['a'], description: 'd', hashtags: ['#h']);
      final back = PublishText.decode(t.encode());
      expect(back.titles, ['a']);
      expect(back.description, 'd');
      expect(PublishText.decode('nope').isEmpty, isTrue);
      expect(PublishText.decode(null).isEmpty, isTrue);
    });

    test('final description puts credit before hashtags', () {
      const t = PublishText(description: 'about', hashtags: ['#a', '#b']);
      expect(finalDescription(t, 'မူရင်း: X'), 'about\n\nမူရင်း: X\n\n#a #b');
    });
  });

  group('output size and presets', () {
    test('original keeps the old behaviour: height fixed, width follows', () {
      expect(outputSize(const RenderSettings(height: 720), 16 / 9), (w: 1280, h: 720));
      expect(outputSize(const RenderSettings(height: 720), 4 / 3), (w: 960, h: 720));
    });

    test('9:16, 1:1, 4:5, 16:9 use the shorter side', () {
      expect(outputSize(const RenderSettings(height: 1080, ratio: OutRatio.r9x16), 16 / 9), (w: 1080, h: 1920));
      expect(outputSize(const RenderSettings(height: 720, ratio: OutRatio.r1x1), 16 / 9), (w: 720, h: 720));
      expect(outputSize(const RenderSettings(height: 1080, ratio: OutRatio.r4x5), 16 / 9), (w: 1080, h: 1350));
      expect(outputSize(const RenderSettings(height: 720, ratio: OutRatio.r16x9), 1), (w: 1280, h: 720));
    });

    test('sizes are always even', () {
      for (final r in OutRatio.values) {
        final s = outputSize(RenderSettings(height: 720, ratio: r), 1.7);
        expect(s.w.isEven && s.h.isEven, isTrue, reason: r.name);
      }
    });

    test('every preset gives a valid shape and a sane bitrate', () {
      for (final p in platformPresets) {
        final s = outputSize(p.settings, 16 / 9);
        expect(s.w > 0 && s.h > 0, isTrue);
        final b = videoBitrate(p.settings);
        expect(b, inInclusiveRange(2000000, 12000000), reason: p.id);
      }
      expect(platformPresets.map((p) => p.id).toSet().length, platformPresets.length);
    });

    test('job carries the output size and fit mode', () {
      final tl = Timeline(pieces: const [VideoPiece(0, 10000)]);
      final j = buildRenderJob(
        name: 'n',
        videoUri: 'file:///v.mp4',
        timeline: tl,
        sourceSubtitles: const [],
        settings: const RenderSettings(height: 720, ratio: OutRatio.r9x16, fill: FillMode.blur),
      );
      expect(j['outW'], 720);
      expect(j['outH'], 1280);
      expect(j['fit'], 'blur');
    });

    test('blur falls back to bars with a freeze frame or a split', () {
      final tl = Timeline(pieces: const [VideoPiece(0, 5000), VideoPiece.freezeAt(5000, 2000)]);
      const st = RenderSettings(ratio: OutRatio.r9x16, fill: FillMode.blur);
      final j = buildRenderJob(name: 'n', videoUri: 'u', timeline: tl, sourceSubtitles: const [], settings: st);
      expect(j['fit'], 'bars');
      final j2 = buildRenderJob(
        name: 'n',
        videoUri: 'u',
        timeline: Timeline(pieces: const [VideoPiece(0, 5000)]),
        sourceSubtitles: const [],
        settings: st,
        splits: const [
          {'s': 0, 'e': 2000, 'src': 0, 'layout': 'leftRight'}
        ],
      );
      expect(j2['fit'], 'bars');
    });

    test('original ratio ignores the fill mode', () {
      final j = buildRenderJob(
        name: 'n',
        videoUri: 'u',
        timeline: Timeline(pieces: const [VideoPiece(0, 5000)]),
        sourceSubtitles: const [],
        settings: const RenderSettings(fill: FillMode.blur),
      );
      expect(j['fit'], 'orig');
    });
  });

  group('sample render', () {
    test('cuts the pieces at the limit and keeps their order', () {
      final tl = Timeline(pieces: const [VideoPiece(0, 5000), VideoPiece(20000, 30000)]);
      final s = sampleTimeline(tl);
      expect(s.pieces.length, 2);
      expect(s.pieces[1].startMs, 20000);
      expect(s.pieces[1].endMs, 23000);
      expect(s.videoMs, sampleMs);
    });

    test('a short edit is left alone; a tiny rest is dropped', () {
      final tl = Timeline(pieces: const [VideoPiece(0, 3000)]);
      expect(sampleTimeline(tl).videoMs, 3000);
      final tl2 = Timeline(pieces: const [VideoPiece(0, 7900), VideoPiece(9000, 9500)]);
      expect(sampleTimeline(tl2).pieces.length, 1);
    });

    test('narration that starts after the limit is dropped', () {
      final tl = Timeline(
        pieces: const [VideoPiece(0, 20000)],
        voices: const [
          VoiceItem(source: 'a', label: 'a', durationMs: 2000, offsetMs: 1000),
          VoiceItem(source: 'b', label: 'b', durationMs: 2000, offsetMs: 9000),
        ],
      );
      expect(sampleTimeline(tl).voices.map((v) => v.source), ['a']);
    });

    test('windows are cut or dropped', () {
      final r = clipWindows([
        {'s': 1000, 'e': 3000},
        {'s': 7000, 'e': 12000},
        {'s': 9000, 'e': 11000},
        {'s': 7900, 'e': 9000},
      ], sampleMs);
      expect(r.length, 2);
      expect(r[1]['e'], sampleMs);
    });
  });
}
