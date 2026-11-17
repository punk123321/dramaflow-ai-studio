import 'dart:convert';

import 'package:aistudio/core/backup.dart';
import 'package:aistudio/core/render_plan.dart';
import 'package:aistudio/core/sub_presets.dart';
import 'package:aistudio/core/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _proj([String name = 'P']) => {
      'name': name,
      'drama_title': 'D',
      'episode': 1,
      'done_mask': 3,
      'status': 'idle',
      'source_video_uri': 'content://x',
      'video_name': null,
      'video_size': null,
      'video_duration_ms': 1000,
      'video_width': null,
      'video_height': null,
      'created_at': 1,
      'updated_at': 2,
    };

void main() {
  group('backup', () {
    test('round trip keeps documents, segments and handoff', () {
      final raw = encodeBackup([
        BackupProject(
          project: _proj(),
          documents: {'timeline': '{"a":1}', 'script': 'မြန်မာ'},
          segments: [
            {'idx': 0, 'start_ms': 0, 'end_ms': 100}
          ],
          handoff: [
            {'task': 't', 'chunk_idx': 0, 'result': 'r'}
          ],
        )
      ], nowMs: 5);
      final r = parseBackup(raw);
      expect(r.error, isNull);
      expect(r.projects.single.project['name'], 'P');
      expect(r.projects.single.documents['script'], 'မြန်မာ');
      expect(r.projects.single.segments.single['end_ms'], 100);
      expect(r.projects.single.handoff.single['result'], 'r');
    });

    test('refuses junk, wrong format, newer version, empty', () {
      expect(parseBackup('nope').error, isNotNull);
      expect(parseBackup('{"format":"other"}').error, isNotNull);
      expect(parseBackup(jsonEncode({'format': backupFormat, 'version': 99, 'projects': []})).error, contains('update'));
      expect(parseBackup(jsonEncode({'format': backupFormat, 'version': 1, 'projects': []})).error, isNotNull);
    });

    test('a damaged project is skipped and counted, good ones kept', () {
      final raw = jsonEncode({
        'format': backupFormat,
        'version': 1,
        'projects': [
          {'project': _proj('ok'), 'documents': {}},
          {'project': {'name': 5}},
          'junk',
        ],
      });
      final r = parseBackup(raw);
      expect(r.projects.length, 1);
      expect(r.skipped, 2);
    });

    test('bad entries inside a project are dropped, not guessed', () {
      final raw = jsonEncode({
        'format': backupFormat,
        'version': 1,
        'projects': [
          {
            'project': _proj(),
            'documents': {'a': 'x', 'b': 3},
            'segments': [
              {'idx': 0, 'start_ms': 0, 'end_ms': 5},
              {'idx': 'x'}
            ],
            'handoff': [
              {'task': 1}
            ],
          }
        ],
      });
      final p = parseBackup(raw).projects.single;
      expect(p.documents.keys, ['a']);
      expect(p.segments.length, 1);
      expect(p.handoff, isEmpty);
    });
  });

  group('subtitle presets and fade', () {
    test('fade survives JSON and is off by default', () {
      expect(const SubStyle().fade, isFalse);
      expect(SubStyle.fromJson(const SubStyle(fade: true).toJson()).fade, isTrue);
      expect(SubStyle.fromJson(const {}).fade, isFalse);
    });

    test('every preset is within limits and matches itself only', () {
      for (final p in subPresets) {
        expect(p.style.size, inInclusiveRange(0.03, 0.09));
        expect(matchingPreset(p.style)?.id, p.id);
      }
      expect(subPresets.map((p) => p.id).toSet().length, subPresets.length);
      expect(matchingPreset(const SubStyle(size: 0.0777)), isNull);
    });
  });

  group('missing edit files', () {
    test('reports gone narration, music and logo; ignores content links', () {
      final t = Timeline(
        voices: const [
          VoiceItem(source: '/a.wav', label: 'A', durationMs: 1, offsetMs: 0),
          VoiceItem(source: 'content://b', label: 'B', durationMs: 1, offsetMs: 0),
        ],
        music: const MusicTrack(source: '/m.mp3', name: 'M', durationMs: 1),
        logo: const LogoItem(path: '/l.png'),
      );
      expect(missingEditFiles(t, (_) => false).length, 3);
      expect(missingEditFiles(t, (_) => true), isEmpty);
    });
  });
}
