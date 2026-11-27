import 'package:aistudio/core/colab_render.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> job([Map<String, Object?> extra = const {}]) => {
      'name': 'x',
      'videoUri': 'content://v',
      'estimateBytes': 5,
      'outW': 1280,
      'outH': 720,
      'fps': 30,
      'pieces': [
        {'s': 0, 'e': 4000},
        {'s': 6000, 'e': 10000, 'sp': 2.0},
      ],
      'voiceLanes': <Object?>[],
      'corners': <Object?>[],
      'music': null,
      'logo': null,
      ...extra,
    };

void main() {
  test('a plain cut with speed, Censor and subtitles is supported', () {
    expect(colabUnsupported(job({'censors': [{'s': 0, 'e': 1000, 'x': .5, 'y': .5, 'w': .3}], 'burn': true, 'subtitles': [{'s': 0, 'e': 1, 't': 'a'}]})), isEmpty);
  });

  test('each feature that is not supported yet is named', () {
    final cases = <String, Object?>{
      'voiceLanes': [[{'uri': 'x'}]],
      'music': {'uri': 'm'},
      'overlays': [{'s': 0}],
      'splits': [{'s': 0}],
      'logo': {'p': 'x'},
      'corners': [{'t': 'x'}],
      'fit': 'blur',
    };
    for (final e in cases.entries) {
      expect(colabUnsupported(job({e.key: e.value})), isNotEmpty, reason: e.key);
    }
    for (final p in <Map<String, Object?>>[
      {'s': 0, 'e': 1000, 'f': 1},
      {'s': 0, 'e': 1000, 'c': [1, 0.5, 0.5]},
      {'s': 0, 'e': 1000, 'z': 1},
      {'s': 0, 'e': 1000, 'l': [0, 0]},
      {'s': 0, 'e': 1000, 'sp': 9.0},
    ]) {
      expect(colabUnsupported(job({'pieces': [p]})), isNotEmpty, reason: '$p');
    }
  });

  test('pieces must be in order, not overlap and not be empty', () {
    expect(colabUnsupported(job({'pieces': [{'s': 5000, 'e': 8000}, {'s': 1000, 'e': 2000}]})), isNotEmpty);
    expect(colabUnsupported(job({'pieces': [{'s': 0, 'e': 5000}, {'s': 4000, 'e': 8000}]})), isNotEmpty);
    expect(colabUnsupported(job({'pieces': [{'s': 3000, 'e': 3000}]})), isNotEmpty);
    expect(colabUnsupported(job({'pieces': <Object?>[]})), isNotEmpty);
  });

  test('the request drops phone-only fields and keeps the rest', () {
    final r = studioRenderRequest(file: 'a.mp4', job: job());
    expect(r['op'], 'render');
    expect(r['file'], 'a.mp4');
    final j = r['job'] as Map;
    expect(j.containsKey('videoUri'), isFalse);
    expect(j.containsKey('estimateBytes'), isFalse);
    expect(j['outW'], 1280);
    expect((j['pieces'] as List).length, 2);
  });

  test('same-size check', () {
    expect(sameVideoSize(100, 100), isTrue);
    expect(sameVideoSize(100, 101), isFalse);
    expect(sameVideoSize(null, 100), isNull);
    expect(sameVideoSize(0, 100), isNull);
  });
}
