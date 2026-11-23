import 'package:aistudio/core/news_video.dart' show JobState;
import 'package:aistudio/core/source_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractLink', () {
    test('Red Note share text with words around the link', () {
      const t = '78 【绝世唐门 第12集 - 小红书】 😆 abc 😆 http://xhslink.com/a/AbC123，复制本条信息';
      expect(extractLink(t), 'http://xhslink.com/a/AbC123');
    });
    test('TikTok share text', () {
      expect(extractLink('Check this https://vm.tiktok.com/ZMabc123/ now'), 'https://vm.tiktok.com/ZMabc123/');
    });
    test('trailing punctuation is dropped', () {
      expect(extractLink('see https://youtu.be/abc123.'), 'https://youtu.be/abc123');
      expect(extractLink('(https://youtu.be/abc123)'), 'https://youtu.be/abc123');
    });
    test('none', () {
      expect(extractLink('no link'), isNull);
      expect(extractLink(''), isNull);
    });
  });

  group('linkKindOf', () {
    test('known sites', () {
      expect(linkKindOf('https://www.youtube.com/watch?v=x'), LinkKind.youtube);
      expect(linkKindOf('https://youtu.be/x'), LinkKind.youtube);
      expect(linkKindOf('https://vm.tiktok.com/x'), LinkKind.tiktok);
      expect(linkKindOf('http://xhslink.com/a/x'), LinkKind.rednote);
      expect(linkKindOf('https://www.xiaohongshu.com/explore/1'), LinkKind.rednote);
      expect(linkKindOf('https://v.douyin.com/x'), LinkKind.douyin);
      expect(linkKindOf('https://b23.tv/x'), LinkKind.bilibili);
      expect(linkKindOf('https://example.com/v.mp4'), LinkKind.other);
    });
    test('look-alike hosts are not matched', () {
      expect(linkKindOf('https://notyoutube.com/x'), LinkKind.other);
      expect(linkKindOf('https://youtube.com.evil.example/x'), LinkKind.other);
    });
    test('every kind has a label', () {
      for (final k in LinkKind.values) {
        expect(linkKindLabels[k], isNotNull);
      }
    });
  });

  group('IngestInfo', () {
    const url = 'https://youtu.be/abc';
    const hour = 3600 * 1000;
    final info = const IngestInfo(url: url, fileUri: 'https://g/f/1', mime: 'video/mp4', durationMs: 60000, title: 'T', source: 'youtube', savedAtMs: 1000);

    test('round trip', () {
      final back = IngestInfo.decode(info.encode())!;
      expect(back.url, url);
      expect(back.fileUri, 'https://g/f/1');
      expect(back.durationMs, 60000);
      expect(back.title, 'T');
      expect(back.source, 'youtube');
      expect(back.savedAtMs, 1000);
    });
    test('bad text decodes to null', () {
      expect(IngestInfo.decode(null), isNull);
      expect(IngestInfo.decode(''), isNull);
      expect(IngestInfo.decode('not json'), isNull);
      expect(IngestInfo.decode('[]'), isNull);
      expect(IngestInfo.decode('{"url":"u","file_uri":"","duration_ms":5}'), isNull);
      expect(IngestInfo.decode('{"url":"u","file_uri":"x"}'), isNull);
    });
    test('missing mime falls back to mp4', () {
      expect(IngestInfo.decode('{"url":"u","file_uri":"x","duration_ms":5}')!.mime, 'video/mp4');
    });
    test('usable for the same link inside the keep time only', () {
      expect(info.usableFor(url, 1000 + 10 * hour), isTrue);
      expect(info.usableFor('  $url ', 1000 + 10 * hour), isTrue);
      expect(info.usableFor('https://youtu.be/other', 1000 + hour), isFalse);
      expect(info.usableFor(url, 1000 + ingestKeepHours * hour), isFalse);
      expect(info.usableFor(url, 500), isFalse); // clock went back
    });
    test('without length it is not usable', () {
      const noDur = IngestInfo(url: url, fileUri: 'x', mime: 'video/mp4', durationMs: 0, savedAtMs: 0);
      expect(noDur.usableFor(url, 10), isFalse);
    });
  });

  group('parseIngestJob', () {
    test('running', () {
      final j = parseIngestJob('{"status":"running","stage":"ဆွဲနေ","progress":30}');
      expect(j.state, JobState.running);
      expect(j.progress, 30);
      expect(j.info, isNull);
    });
    test('done with info', () {
      final j = parseIngestJob('{"status":"done","progress":100,"info":{"file_uri":"u","mime":"video/mp4","duration_ms":5000,"title":"T","source":"tiktok"}}');
      expect(j.state, JobState.done);
      final i = ingestInfoFrom('https://vm.tiktok.com/x', j.info, 7)!;
      expect(i.fileUri, 'u');
      expect(i.durationMs, 5000);
      expect(i.source, 'tiktok');
      expect(i.savedAtMs, 7);
    });
    test('error text is kept', () {
      final j = parseIngestJob('{"status":"error","error":"YouTube က တားထားတယ်"}');
      expect(j.state, JobState.error);
      expect(j.error, contains('YouTube'));
    });
    test('garbage is an error job', () {
      expect(parseIngestJob('<html>').state, JobState.error);
      expect(parseIngestJob('[]').state, JobState.error);
    });
    test('progress is clamped', () {
      expect(parseIngestJob('{"status":"running","progress":900}').progress, 100);
      expect(parseIngestJob('{"status":"running","progress":-5}').progress, 0);
    });
    test('an answer without file address or length gives no record', () {
      expect(ingestInfoFrom('u', null, 1), isNull);
      expect(ingestInfoFrom('u', {'file_uri': '', 'duration_ms': 5}, 1), isNull);
      expect(ingestInfoFrom('u', {'file_uri': 'x', 'duration_ms': 0}, 1), isNull);
      expect(ingestInfoFrom('u', {'file_uri': 'x'}, 1), isNull);
    });
  });
}
