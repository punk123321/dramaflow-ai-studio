import 'package:aistudio/core/render_plan.dart';
import 'package:aistudio/core/srt.dart';
import 'package:aistudio/core/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

const pieces = [VideoPiece(0, 10000), VideoPiece(20000, 30000)];

void main() {
  group('size estimate', () {
    test('720p 30 fps: about 4 Mbps video + 128 kbps audio', () {
      final b = estimateBytes(60000, const RenderSettings());
      // (4,000,000 + 128,000) bits/s * 60 s / 8 * 1.05 = 32,508,000
      expect(b, closeTo(32508000, 100));
    });
    test('1080p is bigger than 720p and a longer video is bigger', () {
      expect(estimateBytes(60000, const RenderSettings(height: 1080)), greaterThan(estimateBytes(60000, const RenderSettings())));
      expect(estimateBytes(120000, const RenderSettings()), greaterThan(estimateBytes(60000, const RenderSettings())));
    });
    test('zero length gives zero', () {
      expect(estimateBytes(0, const RenderSettings()), 0);
    });
    test('high frame rate raises the bitrate', () {
      expect(videoBitrate(const RenderSettings(fps: 60)), greaterThan(videoBitrate(const RenderSettings())));
    });
  });

  group('voice lanes', () {
    VoiceItem v(int off, int dur, [String n = 'a']) => VoiceItem(source: n, label: n, durationMs: dur, offsetMs: off);

    test('clips one after another stay in one lane, sorted', () {
      final lanes = assignVoiceLanes([v(5000, 1000, 'b'), v(0, 5000, 'a')]);
      expect(lanes.length, 1);
      expect(lanes.first.map((x) => x.label), ['a', 'b']);
    });
    test('overlapping clips need a second lane', () {
      final lanes = assignVoiceLanes([v(0, 5000, 'a'), v(3000, 4000, 'b'), v(6000, 1000, 'c')]);
      expect(lanes.length, 2);
      for (final lane in lanes) {
        for (var i = 1; i < lane.length; i++) {
          expect(lane[i].offsetMs >= lane[i - 1].endMs, isTrue);
        }
      }
      expect(lanes.expand((l) => l).length, 3);
    });
    test('no voices gives no lanes', () {
      expect(assignVoiceLanes(const []), isEmpty);
    });
  });

  group('render job', () {
    final subs = [const SrtEntry(1, 21000, 23000, 'မင်္ဂလာပါ'), const SrtEntry(2, 12000, 15000, 'cut out')];
    const tl = Timeline(
      pieces: pieces,
      voices: [VoiceItem(source: '/data/user/0/app/files/a.wav', label: 'A', durationMs: 4000, offsetMs: 500, volume: 0.9)],
      music: MusicTrack(source: 'content://media/m', name: 'm', durationMs: 60000, volume: 0.2, loop: true),
      subtitleOffsetMs: 100,
      originalVolume: 0.0,
    );

    test('contains pieces, lanes, music and remapped subtitles', () {
      final j = buildRenderJob(name: 'n', videoUri: 'content://v', timeline: tl, sourceSubtitles: subs, settings: const RenderSettings(height: 1080, fps: 25));
      expect(j['name'], 'n');
      expect(j['videoUri'], 'content://v');
      expect(j['height'], 1080);
      expect(j['fps'], 25);
      expect(j['pieces'], [
        {'s': 0, 'e': 10000, 'z': 0},
        {'s': 20000, 'e': 30000, 'z': 0},
      ]);
      final lanes = j['voiceLanes'] as List;
      expect(lanes.length, 1);
      final first = (lanes.first as List).first as Map;
      expect(first['uri'], 'file:///data/user/0/app/files/a.wav'); // app files become file links
      expect(first['off'], 500);
      expect(first['vol'], 0.9);
      expect((j['music'] as Map)['uri'], 'content://media/m'); // user files stay as they are
      final s = j['subtitles'] as List;
      expect(s.length, 1); // the cut-out one is gone
      expect((s.first as Map)['s'], 11100); // 21000 -> piece 2 at 10000 +1000 +100 offset
      expect((s.first as Map)['t'], 'မင်္ဂလာပါ');
      expect(j['estimateBytes'], estimateBytes(20000, const RenderSettings(height: 1080, fps: 25)));
    });

    test('style, corner texts, logo, zoom and aspect go into the job', () {
      const t = Timeline(
        pieces: [VideoPiece(0, 10000, ZoomMode.zoomIn)],
        style: SubStyle(size: 0.08, color: 0xFFFFFF00, top: true),
        corners: [CornerText(text: 'my channel', corner: Corner.topLeft), CornerText(text: '   ')],
        logo: LogoItem(path: '/a/logo.png', corner: Corner.bottomRight),
      );
      final j = buildRenderJob(name: 'n', videoUri: 'v', timeline: t, sourceSubtitles: const [], settings: const RenderSettings(), aspect: 9 / 16);
      expect((j['pieces'] as List).first, {'s': 0, 'e': 10000, 'z': 1});
      expect(j['aspect'], 9 / 16);
      expect((j['subStyle'] as Map)['size'], 0.08);
      expect((j['subStyle'] as Map)['top'], isTrue);
      final c = j['corners'] as List;
      expect(c.length, 1); // the blank one is dropped
      expect((c.first as Map)['t'], 'my channel');
      expect((c.first as Map)['c'], Corner.topLeft.index);
      expect((j['logo'] as Map)['path'], '/a/logo.png');
    });

    test('no music means null', () {
      final j = buildRenderJob(name: 'n', videoUri: 'v', timeline: const Timeline(pieces: pieces), sourceSubtitles: const [], settings: const RenderSettings());
      expect(j['music'], isNull);
      expect(j['voiceLanes'], isEmpty);
    });
  });

  group('blockers', () {
    test('no video', () {
      expect(renderBlockers(hasVideo: false, timeline: const Timeline(pieces: pieces), sourceMs: 60000), isNotEmpty);
    });
    test('empty timeline', () {
      expect(renderBlockers(hasVideo: true, timeline: const Timeline(), sourceMs: 60000), isNotEmpty);
    });
    test('valid timeline can render, warnings do not block', () {
      expect(renderBlockers(hasVideo: true, timeline: const Timeline(pieces: pieces), sourceMs: 60000), isEmpty);
    });
    test('piece past the end blocks', () {
      expect(renderBlockers(hasVideo: true, timeline: const Timeline(pieces: [VideoPiece(0, 90000)]), sourceMs: 60000), isNotEmpty);
    });
  });

  test('safeFileName', () {
    expect(safeFileName('a/b:c*d'), 'a_b_c_d');
    expect(safeFileName('   '), 'dramaflow');
    expect(safeFileName('x' * 100).length, 60);
    expect(safeFileName('ဇာတ်လမ်း 1'), 'ဇာတ်လမ်း 1');
  });
}
