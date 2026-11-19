import 'dart:convert';

import 'package:aistudio/core/transformative_plan.dart';
import 'package:aistudio/data/app_db.dart';
import 'package:aistudio/data/handoff_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('TE plan round-trips mode, tools, instructions and ops', () {
    final plan = TransformativePlan(
      mode: TransformMode.aiAssisted,
      enabledTools: const {TransformTool.smartCut, TransformTool.pictureInPicture},
      instructions: 'Explain key scenes.',
      ops: const [
        TransformOp(
          id: 'a',
          tool: TransformTool.freezeFrame,
          startMs: 1000,
          endMs: 4000,
          note: 'key moment',
          params: {'hold': 2},
          status: OpStatus.approved,
        ),
      ],
    );
    final d = TransformativePlan.decode(plan.encode());
    expect(d.mode, TransformMode.aiAssisted);
    expect(d.enabledTools, plan.enabledTools);
    expect(d.instructions, 'Explain key scenes.');
    expect(d.version, transformPlanVersion);
    expect(d.ops.single.tool, TransformTool.freezeFrame);
    expect(d.ops.single.params['hold'], 2);
    expect(d.ops.single.status, OpStatus.approved);
  });

  test('unknown values and malformed JSON safely fall back', () {
    final d = TransformativePlan.decode('{"mode":"future","tools":["unknown"]}');
    expect(d.mode, TransformMode.hybrid);
    expect(d.enabledTools, isEmpty);
    expect(TransformativePlan.decode('{bad json').mode, TransformMode.hybrid);
    expect(TransformativePlan.decode('[1,2]').ops, isEmpty);
    expect(TransformativePlan.decode(null).ops, isEmpty);
  });

  test('version 1 file (no ops) loads and is saved as the current version', () {
    final d = TransformativePlan.decode('{"version":1,"mode":"manual","tools":["smartCut"],"instructions":"x"}');
    expect(d.version, 1);
    expect(d.ops, isEmpty);
    expect(d.mode, TransformMode.manual);
    final out = jsonDecode(d.encode()) as Map;
    expect(out['version'], transformPlanVersion);
    expect(out['tools'], ['smartCut']);
  });

  test('a newer file keeps its version, unknown tools, unknown ops and extra fields', () {
    const raw = '{"version":9,"mode":"manual","tools":["smartCut","hologram"],'
        '"instructions":"","ops":[{"id":"z","tool":"hologram","s":0,"e":1},'
        '{"id":"b","tool":"smartCut","s":0,"e":1000,"status":"approved"}],'
        '"future":{"a":1}}';
    final d = TransformativePlan.decode(raw);
    expect(d.fromNewerVersion, isTrue);
    expect(d.ops.length, 1);
    final out = jsonDecode(d.copyWith(instructions: 'edited').encode()) as Map;
    expect(out['version'], 9);
    expect(out['tools'], containsAll(['smartCut', 'hologram']));
    expect((out['ops'] as List).length, 2);
    expect(out['future'], {'a': 1});
    expect(out['instructions'], 'edited');
  });

  test('unknown fields inside a known operation survive a load and save', () {
    const raw = '{"version":2,"mode":"manual","tools":[],"instructions":"","ops":[{"id":"a","tool":"smartCut","s":0,"e":1000,'
        '"status":"approved","src":"ai","futureField":{"k":1},"conf":0.9}]}';
    final d = TransformativePlan.decode(raw);
    final approved = d.setOpStatus('a', OpStatus.rejected);
    final out = jsonDecode(approved.encode()) as Map;
    final op = (out['ops'] as List).single as Map;
    expect(op['futureField'], {'k': 1});
    expect(op['conf'], 0.9);
    expect(op['status'], 'rejected');
  });

  test('approval: proposals and unknown statuses are never runnable', () {
    final p = TransformOp.proposal(id: 'p', tool: TransformTool.smartCut, startMs: 0, endMs: 1000);
    expect(p.status, OpStatus.proposed);
    expect(p.source, OpSource.ai);
    expect(p.runnable, isFalse);
    final odd = TransformOp.fromJson({'id': 'q', 'tool': 'smartCut', 's': 0, 'e': 5, 'status': 'whatever'})!;
    expect(odd.status, OpStatus.proposed);
    expect(odd.runnable, isFalse);
    var plan = TransformativePlan(ops: [p]);
    expect(plan.approvedOps, isEmpty);
    expect(plan.pendingOps.length, 1);
    plan = plan.setOpStatus('p', OpStatus.approved);
    expect(plan.approvedOps.length, 1);
    plan = plan.setOpStatus('p', OpStatus.rejected);
    expect(plan.approvedOps, isEmpty);
    expect(plan.removeOp('p').ops, isEmpty);
  });

  test('invalid op ranges are not runnable; bad op maps are kept, not crashed on', () {
    const bad = TransformOp(id: 'x', tool: TransformTool.smartCut, startMs: 5000, endMs: 1000, status: OpStatus.approved);
    expect(bad.valid, isFalse);
    expect(bad.runnable, isFalse);
    expect(TransformOp.fromJson('nope'), isNull);
    expect(TransformOp.fromJson({'id': '', 'tool': 'smartCut', 's': 0, 'e': 1}), isNull);
    expect(TransformOp.fromJson({'id': 'a', 'tool': 'smartCut', 's': 'x', 'e': 1}), isNull);
  });

  test('tool status says only what exists today', () {
    expect(TransformTool.freezeFrame.status, ToolStatus.rendered);
    expect(TransformTool.cropReframe.status, ToolStatus.rendered);
    expect(TransformTool.pictureInPicture.status, ToolStatus.rendered);
    expect(TransformTool.smartCut.status, ToolStatus.rendered);
    expect(TransformTool.motionGraphics.status, ToolStatus.rendered);
    expect(TransformTool.soundDesign.status, ToolStatus.rendered);
    expect(TransformTool.splitScreen.status, ToolStatus.experimental);
    expect(TransformTool.colorGrade.status, ToolStatus.rendered);
    expect(TransformTool.commentaryVoiceOver.status, ToolStatus.inStudio);
    expect(TransformTool.blur.status, ToolStatus.rendered);
    expect(TransformTool.mirrorFlip.status, ToolStatus.rendered);
  });

  group('per-project storage', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      await AppDb.closeForTest();
      await databaseFactory.deleteDatabase(p.join(await databaseFactory.getDatabasesPath(), 'dramaflow.db'));
    });

    test('plans are stored separately for each project, copied and untouched by other docs', () async {
      final repo = HandoffRepo();
      final a = const TransformativePlan(instructions: 'A', enabledTools: {TransformTool.smartCut});
      final b = const TransformativePlan(instructions: 'B');
      await repo.setDoc(9001, DocKind.transformativePlan, a.encode());
      await repo.setDoc(9002, DocKind.transformativePlan, b.encode());
      await repo.setDoc(9001, DocKind.timeline, 'tl');
      expect(TransformativePlan.decode(await repo.getDoc(9001, DocKind.transformativePlan)).instructions, 'A');
      expect(TransformativePlan.decode(await repo.getDoc(9002, DocKind.transformativePlan)).instructions, 'B');
      expect(await repo.getDoc(9003, DocKind.transformativePlan), isNull);

      await repo.copyProject(9001, 9004);
      final c = TransformativePlan.decode(await repo.getDoc(9004, DocKind.transformativePlan));
      expect(c.instructions, 'A');
      expect(c.enabledTools, {TransformTool.smartCut});
      expect(await repo.getDoc(9004, DocKind.timeline), 'tl');

      await repo.setDoc(9001, DocKind.transformativePlan, b.encode());
      expect(TransformativePlan.decode(await repo.getDoc(9004, DocKind.transformativePlan)).instructions, 'A');
    });
  });
}
