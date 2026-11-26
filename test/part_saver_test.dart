import 'package:flutter_test/flutter_test.dart';

import 'package:aistudio/platform/part_saver.dart';

void main() {
  test('a full run is summarised as done', () {
    expect(partsRunSummary(total: 7, saved: 7, what: 'Segment'), 'Segment 7 ခု အားလုံး ထုတ်ပြီး Gallery ထဲ သိမ်းပြီး');
  });

  test('a stopped run says how far it got and why', () {
    final t = partsRunSummary(total: 7, saved: 1, what: 'Segment', stoppedAt: '#2', why: 'ဖုန်းမှာ နေရာ မလောက်တော့ဘူး');
    expect(t, contains('7 ခုထဲက 1 ခု'));
    expect(t, contains('#2 မှာ ရပ်သွားတယ်'));
    expect(t, contains('နေရာ မလောက်'));
  });

  test('a run with fewer saved than planned is never called done', () {
    expect(partsRunSummary(total: 3, saved: 2, what: 'အပိုင်း'), isNot(contains('အားလုံး')));
  });

  test('Gallery failures get a Burmese reason', () {
    expect(galleryFailText('PlatformException(use_export, x)'), contains('Android'));
    expect(galleryFailText('java.io.IOException: ENOSPC (No space left on device)'), contains('နေရာ'));
    expect(galleryFailText('missing: The video file is gone'), contains('ပျောက်'));
    expect(galleryFailText('x' * 300).length, lessThan(160));
  });
}
