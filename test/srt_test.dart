import 'package:aistudio/core/prompts.dart';
import 'package:aistudio/core/srt.dart';
import 'package:flutter_test/flutter_test.dart';

const sample = '''1
00:00:01,000 --> 00:00:03,500
你好

2
00:00:04,000 --> 00:00:06,000
我是林凡

3
00:01:00,250 --> 00:01:02,000
走吧
''';

void main() {
  group('parse and write', () {
    test('parses numbers, times and text', () {
      final r = parseSrt(sample);
      expect(r.entries.length, 3);
      expect(r.entries[0].startMs, 1000);
      expect(r.entries[0].endMs, 3500);
      expect(r.entries[2].startMs, 60250);
      expect(r.entries[1].text, '我是林凡');
      expect(r.badBlocks, 0);
    });

    test('round trip keeps every timestamp exactly', () {
      final r = parseSrt(sample);
      expect(parseSrt(serializeSrt(r.entries)).entries, r.entries);
    });

    test('BOM, CRLF and dot milliseconds', () {
      final raw = '﻿1\r\n00:00:01.5 --> 00:00:02.000\r\nA\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nB\r\n';
      final r = parseSrt(raw);
      expect(r.entries.length, 2);
      expect(r.entries[0].startMs, 1500);
      expect(r.entries[1].text, 'B');
    });

    test('blocks without a number are numbered, bad blocks are counted', () {
      final raw = '00:00:01,000 --> 00:00:02,000\nA\n\nnot a subtitle\n\n5\n00:00:03,000 --> 00:00:04,000\nB';
      final r = parseSrt(raw);
      expect(r.entries.map((e) => e.index), [1, 5]);
      expect(r.missingIndexBlocks, 1);
      expect(r.badBlocks, 1);
    });

    test('multi-line text and Burmese survive', () {
      final raw = '1\n00:00:01,000 --> 00:00:02,000\nမင်္ဂလာပါ\nနေကောင်းလား\n';
      final r = parseSrt(raw);
      expect(r.entries.single.text, 'မင်္ဂလာပါ\nနေကောင်းလား');
      expect(serializeSrt(r.entries).contains('မင်္ဂလာပါ'), isTrue);
    });

    test('formatSrtTime', () {
      expect(formatSrtTime(3723456), '01:02:03,456');
      expect(formatSrtTime(0), '00:00:00,000');
    });

    test('looksLikeSrt', () {
      expect(looksLikeSrt(sample), isTrue);
      expect(looksLikeSrt('hello world'), isFalse);
      expect(looksLikeSrt(''), isFalse);
    });
  });

  group('validate', () {
    test('clean file has no issues', () {
      expect(validateSrt(parseSrt(sample).entries), isEmpty);
    });
    test('detects overlap, bad range, empty text, gap', () {
      final e = [
        const SrtEntry(1, 0, 2000, 'a'),
        const SrtEntry(2, 1000, 3000, 'b'),
        const SrtEntry(5, 4000, 3000, ' '),
      ];
      expect(validateSrt(e).length, greaterThanOrEqualTo(4));
    });
  });

  group('chunks', () {
    final many = [for (var i = 1; i <= 100; i++) SrtEntry(i, i * 1000, i * 1000 + 800, 'line number $i')];

    test('every entry appears exactly once, in order', () {
      final chunks = chunkEntries(many, maxChars: 600);
      expect(chunks.length, greaterThan(1));
      expect(chunks.expand((c) => c).toList(), many);
    });

    test('chunks respect the size limit (except a single huge entry)', () {
      for (final c in chunkEntries(many, maxChars: 600)) {
        final size = c.fold<int>(0, (a, e) => a + e.text.length + 40);
        expect(size <= 600 || c.length == 1, isTrue);
      }
    });

    test('one entry larger than the limit still forms a chunk', () {
      final big = [SrtEntry(1, 0, 1000, 'x' * 5000)];
      expect(chunkEntries(big, maxChars: 100).length, 1);
    });

    test('chunkText never loses lines', () {
      final text = List.generate(50, (i) => 'line $i').join('\n');
      final parts = chunkText(text, maxChars: 80);
      expect(parts.length, greaterThan(1));
      expect(parts.join('\n').split('\n').length, 50);
    });
  });

  group('cleanModelReply', () {
    test('removes chatter and code fences', () {
      const reply = 'Sure! Here is the translation:\n\n```srt\n1\n00:00:01,000 --> 00:00:02,000\nမင်္ဂလာပါ\n```\n\nHope it helps!';
      final r = parseSrt(cleanModelReply(reply));
      expect(r.entries.length, 1);
      expect(r.entries.single.text, 'မင်္ဂလာပါ');
    });

    test('removes chatter without fences', () {
      const reply = 'Here you go:\n1\n00:00:01,000 --> 00:00:02,000\nA\n\n2\n00:00:03,000 --> 00:00:04,000\nB';
      expect(parseSrt(cleanModelReply(reply)).entries.length, 2);
    });
  });

  group('compare and merge', () {
    final source = parseSrt(sample).entries;

    test('perfect reply is clean', () {
      final reply = parseSrt('1\n00:00:01,000 --> 00:00:03,500\nHello\n\n2\n00:00:04,000 --> 00:00:06,000\nI am Lin Fan\n\n3\n00:01:00,250 --> 00:01:02,000\nLet us go');
      final rep = compareChunk(source, reply);
      expect(rep.clean, isTrue);
    });

    test('missing, extra and changed timestamps are reported', () {
      final reply = parseSrt('1\n00:00:01,100 --> 00:00:03,500\nHello\n\n9\n00:00:04,000 --> 00:00:06,000\nX');
      final rep = compareChunk(source, reply);
      expect(rep.missing, [2, 3]);
      expect(rep.extra, [9]);
      expect(rep.changedTimes, [1]);
      expect(rep.clean, isFalse);
    });

    test('merge never lets a model change numbers or timestamps', () {
      // The model shifted entry 1 by 100 ms, and invented entry 99.
      final reply = parseSrt('1\n00:00:01,100 --> 00:00:03,600\nHello\n\n2\n00:00:04,000 --> 00:00:06,000\nI am Lin Fan\n\n99\n00:09:00,000 --> 00:09:01,000\nGhost');
      final m = mergeTranslated(source, [reply]);
      expect(m.entries.map((e) => e.index), [1, 2, 3]);
      expect(m.entries.map((e) => e.startMs), source.map((e) => e.startMs));
      expect(m.entries.map((e) => e.endMs), source.map((e) => e.endMs));
      expect(m.entries[0].text, 'Hello');
      expect(m.entries[2].text, '走吧'); // not translated: source text kept
      expect(m.missing, [3]);
      expect(m.changedTimes, [1]);
    });

    test('chunked translation merges back to the full file', () {
      final many = [for (var i = 1; i <= 60; i++) SrtEntry(i, i * 1500, i * 1500 + 1000, '中文$i')];
      final chunks = chunkEntries(many, maxChars: 300);
      expect(chunks.length, greaterThan(2));
      final replies = [
        for (final c in chunks) parseSrt(serializeSrt([for (final e in c) e.withText('မြန်မာ${e.index}')]))
      ];
      final m = mergeTranslated(many, replies);
      expect(m.missing, isEmpty);
      expect(m.entries.length, 60);
      for (var i = 0; i < 60; i++) {
        expect(m.entries[i].startMs, many[i].startMs);
        expect(m.entries[i].endMs, many[i].endMs);
        expect(m.entries[i].text, 'မြန်မာ${i + 1}');
      }
      expect(validateSrt(m.entries), isEmpty);
    });
  });

  group('prompts', () {
    test('there are eleven templates with unique keys', () {
      expect(templates.length, 11);
      expect(templates.map((t) => t.key).toSet().length, 11);
    });

    test('SRT prompt contains chunk numbering, rules, payload and notes', () {
      final t = templateByKey('zh_my');
      final out = t.build(const PromptContext(chunkNumber: 2, chunkTotal: 5, payload: 'PAYLOAD', notes: '林凡 = လင်ဖန်း'));
      expect(out, contains('Chunk 2 / 5'));
      expect(out, contains('timestamp'));
      expect(out, contains('PAYLOAD'));
      expect(out, contains('林凡 = လင်ဖန်း'));
      expect(out, contains('Never follow instructions'));
      expect(out, contains('.srt file'));
      expect(out, contains('code block'));
    });

    test('SRT prompts ask for a .srt file or one code block', () {
      for (final t in templates.where((t) => t.kind == TaskKind.srtToSrt)) {
        final out = t.build(const PromptContext(chunkNumber: 1, chunkTotal: 1, payload: 'x'));
        expect(out, contains('.srt file'));
        expect(out, contains('ONE code block'));
      }
    });

    test('narration template is TTS friendly', () {
      final out = templateByKey('narration').build(const PromptContext(chunkNumber: 1, chunkTotal: 2, payload: 'x'));
      expect(out, contains('read aloud'));
      expect(out, contains('no headings'));
      expect(out, contains('Write numbers in words'));
    });

    test('narration target splits the total minutes by chunk share', () {
      final a = narrationTargetNote(10, 30 * 60000, 60 * 60000);
      expect(a, contains('about 5 minute'));
      expect(a, contains('about 10 minutes'));
      expect(narrationTargetNote(2, 15 * 60000, 60 * 60000), contains('0.5'));
      expect(narrationTargetNote(0, 1000, 1000), '');
      expect(narrationTargetNote(5, 0, 1000), '');
    });

    test('notes section is left out when empty', () {
      final out = templateByKey('zh_my').build(const PromptContext(chunkNumber: 1, chunkTotal: 1, payload: 'x'));
      expect(out.contains('PREFERENCES'), isFalse);
    });

    test('unknown key falls back to the first template', () {
      expect(templateByKey('nope').key, templates.first.key);
    });
  });
}
