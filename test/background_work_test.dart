import 'package:aistudio/platform/background_work.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <Map<Object?, Object?>>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.dramaflow.aistudio/render'),
      (call) async {
        if (call.method == 'renderKeepAlive') calls.add(Map<Object?, Object?>.from(call.arguments as Map));
        return null;
      },
    );
  });

  test('the service stays on until the last job ends', () async {
    await BackgroundWork.begin('A', 'one');
    await BackgroundWork.begin('B', 'two');
    expect(BackgroundWork.active, 2);
    await BackgroundWork.end();
    expect(BackgroundWork.active, 1);
    expect(calls.where((c) => c['on'] == false), isEmpty);
    await BackgroundWork.end();
    expect(BackgroundWork.active, 0);
    expect(calls.last['on'], false);
  });

  test('run lets go even when the body throws', () async {
    await expectLater(BackgroundWork.run('A', 'x', () async => throw StateError('no')), throwsStateError);
    expect(BackgroundWork.active, 0);
    expect(calls.last['on'], false);
  });

  test('update is ignored when nothing runs and is rate limited', () async {
    await BackgroundWork.update('x', percent: 10);
    expect(calls, isEmpty);
    await BackgroundWork.begin('A', 'start');
    final n = calls.length;
    await BackgroundWork.update('same quickly', percent: 1);
    await BackgroundWork.update('same quickly', percent: 2);
    expect(calls.length, n, reason: 'two updates within 2 s are held back');
    await BackgroundWork.end();
  });

  test('an extra end() does nothing', () async {
    await BackgroundWork.end();
    expect(BackgroundWork.active, 0);
  });
}
