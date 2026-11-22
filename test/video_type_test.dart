import 'package:flutter_test/flutter_test.dart';

import 'package:aistudio/core/video_type.dart';

void main() {
  List<int> b(String s) => s.codeUnits;

  test('mp4, mov and 3gp are told apart by the brand after ftyp', () {
    expect(sniffVideoKind([0, 0, 0, 24, ...b('ftypisom')]).mime, 'video/mp4');
    expect(sniffVideoKind([0, 0, 0, 20, ...b('ftypqt  ')]).mime, 'video/quicktime');
    expect(sniffVideoKind([0, 0, 0, 20, ...b('ftyp3gp4')]).mime, 'video/3gpp');
  });

  test('webm, avi, flv are found; unknown or short input falls back to mp4', () {
    expect(sniffVideoKind([0x1A, 0x45, 0xDF, 0xA3, 1, 2, 3, 4]).mime, 'video/webm');
    expect(sniffVideoKind([...b('RIFF'), 0, 0, 0, 0, ...b('AVI '), 0, 0, 0, 0]).mime, 'video/avi');
    expect(sniffVideoKind([...b('FLV'), 1, 5, 0, 0, 0, 9]).mime, 'video/x-flv');
    expect(sniffVideoKind([1, 2, 3]).mime, 'video/mp4');
    expect(sniffVideoKind(const []).mime, 'video/mp4');
  });
}
