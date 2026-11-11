import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:voxflow/voxflow.dart';

void main() {
  group('Pin compatibility, graph validation & topological sorting', () {
    test('enforces typed pin connections and replaces occupied single inputs', () {
      final g = FlowGraph();
      final start = g.addNode('event.start');
      final a = g.addNode('math.constFloat', properties: {'value': 3.0});
      final b = g.addNode('math.constInt', properties: {'value': 4});
      final add = g.addNode('math.add');

      // Exec pin cannot connect to float input
      expect(() => g.connect(start.id, 'out', add.id, 'a'), throwsArgumentError);
      expect(g.tryConnect(start.id, 'out', add.id, 'a'), isNull);

      // Float & int implicit coercion both connect cleanly
      g.connect(a.id, 'value', add.id, 'a');
      g.connect(b.id, 'value', add.id, 'b');
      expect(g.links.length, 2);

      // Rewiring 'b' replaces the prior wire automatically
      g.connect(a.id, 'value', add.id, 'b');
      expect(g.links.length, 2);

      final eval = DataflowEvaluator(g);
      expect(eval.evaluateOutput(add.id, 'result'), closeTo(6.0, 1e-6));
    });

    test('detects data cycles via topological sort and runtime pull guard', () {
      final g = FlowGraph();
      final add1 = g.addNode('math.add', id: 'add1');
      final add2 = g.addNode('math.add', id: 'add2');

      g.connect(add1.id, 'result', add2.id, 'a');
      expect(g.hasCycles(), isFalse);
      expect(g.topologicalOrder(), equals(['add1', 'add2']));

      g.connect(add2.id, 'result', add1.id, 'a');
      expect(g.hasCycles(), isTrue);
      expect(g.validate().hasDataCycle, isTrue);

      final eval = DataflowEvaluator(g);
      expect(() => eval.evaluateOutput('add2', 'result'), throwsStateError);
    });
  });

  group('DataflowEvaluator memoized pull & vector/math nodes', () {
    test('evaluates shared pure subgraph with single upstream pass per evaluation', () {
      var evalCalls = 0;
      final reg = FlowNodeRegistry()
        ..register(FlowNodeDef(
          typeId: 'custom.probe',
          title: 'Probe',
          category: 'Custom',
          inputs: const [PinDef.input('x', 'X', PinType.floatVal, defaultValue: 0.0)],
          outputs: const [PinDef.output('out', 'Out', PinType.floatVal)],
          evaluate: (ctx) {
            evalCalls++;
            ctx.writeOutput('out', ctx.readFloat('x') * 2.0);
          },
        ));

      final g = FlowGraph(registry: reg);
      final probe = g.addNode('custom.probe', inputs: {'x': 5.0}); // outputs 10
      final mul = g.addNode('math.mul');
      g.connect(probe.id, 'out', mul.id, 'a');
      g.connect(probe.id, 'out', mul.id, 'b');

      final runner = FlowRunner(g);
      expect(runner.evaluateOutput(mul.id, 'result'), closeTo(100.0, 1e-6));
      expect(evalCalls, 1); // diamond DAG pulled probe only once!
    });

    test('computes trig, remap, vector normalization and color lerp accurately', () {
      final g = FlowGraph();
      final makeV = g.addNode('vec.make3', inputs: {'x': 3.0, 'y': 0.0, 'z': 4.0});
      final normV = g.addNode('vec.normalize3');
      final lenV = g.addNode('vec.length3');
      final remap = g.addNode(
        'math.remap',
        inputs: {'inMin': 0.0, 'inMax': 10.0, 'outMin': 100.0, 'outMax': 200.0},
      );
      final sinN = g.addNode('math.sin', inputs: {'x': math.pi / 2});

      g.connect(makeV.id, 'vec', normV.id, 'v');
      g.connect(makeV.id, 'vec', lenV.id, 'v');
      g.connect(lenV.id, 'length', remap.id, 'value');

      final ev = DataflowEvaluator(g);
      final v = ev.evaluateOutput(normV.id, 'result') as FlowVec3;
      expect(v.x, closeTo(0.6, 1e-6));
      expect(v.z, closeTo(0.8, 1e-6));
      expect(ev.evaluateOutput(remap.id, 'result'), closeTo(150.0, 1e-5));
      expect(ev.evaluateOutput(sinN.id, 'result'), closeTo(1.0, 1e-6));
    });
  });

  group('FlowRunner Blueprint exec, loops, latent delays & subgraphs', () {
    test('executes Sequence, ForLoop, SetVariable invalidation, Branch & Signals', () {
      final g = FlowGraph();
      g.blackboard.set('sum', 0);

      final start = g.addNode('event.start');
      final loop = g.addNode('flow.forLoop', inputs: {'firstIndex': 1, 'lastIndex': 4});
      final getSum = g.addNode('var.get', properties: {'name': 'sum'});
      final add = g.addNode('math.add');
      final setSum = g.addNode('var.set', properties: {'name': 'sum'});

      final getFinal = g.addNode('var.get', properties: {'name': 'sum'});
      final cmp = g.addNode('logic.compare', inputs: {'b': 10.0}, properties: {'op': '=='});
      final branch = g.addNode('flow.branch');
      final emitTrue = g.addNode('signal.emit', inputs: {'payload': 'ok'}, properties: {'signal': 'matched'});
      final logTrue = g.addNode('debug.print', inputs: {'message': 'Total=10'});

      g.connect(start.id, 'out', loop.id, 'in');
      // Loop body: sum = sum + index
      g.connect(loop.id, 'loopBody', setSum.id, 'in');
      g.connect(getSum.id, 'value', add.id, 'a');
      g.connect(loop.id, 'index', add.id, 'b');
      g.connect(add.id, 'result', setSum.id, 'value');

      // After loop completes: branch on sum == 10
      g.connect(loop.id, 'completed', branch.id, 'in');
      g.connect(getFinal.id, 'value', cmp.id, 'a');
      g.connect(cmp.id, 'result', branch.id, 'condition');
      g.connect(branch.id, 'true', emitTrue.id, 'in');
      g.connect(emitTrue.id, 'out', logTrue.id, 'in');

      final runner = FlowRunner(g);
      runner.triggerStart();

      expect((runner.blackboard.get('sum') as num).toInt(), 10);
      expect(runner.trace.signals, [('matched', 'ok')]);
      expect(runner.trace.logs, ['Total=10']);
    });

    test('handles non-blocking Delay timers and DoOnce with reset across frames', () {
      final g = FlowGraph();
      final evt = g.addNode('event.custom', properties: {'event': 'Fire'});
      final once = g.addNode('flow.doOnce');
      final delay = g.addNode('flow.delay', inputs: {'seconds': 0.5});
      final emit = g.addNode('signal.emit', properties: {'signal': 'afterDelay'});
      final resetEvt = g.addNode('event.custom', properties: {'event': 'ResetGate'});

      g.connect(evt.id, 'out', once.id, 'in');
      g.connect(once.id, 'completed', delay.id, 'in');
      g.connect(delay.id, 'completed', emit.id, 'in');
      g.connect(resetEvt.id, 'out', once.id, 'reset');

      final runner = FlowRunner(g);

      // Firing twice only arms 1 delay because DoOnce blocks the second trigger
      runner.triggerEvent('Fire');
      runner.triggerEvent('Fire');
      expect(runner.activeDelayCount, 1);
      expect(runner.trace.signals, isEmpty);

      runner.step(0.3);
      expect(runner.activeDelayCount, 1);
      expect(runner.trace.signals, isEmpty);

      runner.step(0.25);
      expect(runner.activeDelayCount, 0);
      expect(runner.trace.signals.length, 1);

      // Reset DoOnce and fire again
      runner.triggerEvent('ResetGate');
      runner.triggerEvent('Fire');
      expect(runner.activeDelayCount, 1);
      runner.step(0.5);
      expect(runner.trace.signals.length, 2);
    });

    test('executes nested subgraphs and preserves full graph via JSON round-trip', () {
      final sub = FlowGraph(name: 'BoostHealth');
      final sStart = sub.addNode('event.start');
      final sGet = sub.addNode('var.get', properties: {'name': 'hp'});
      final sAdd = sub.addNode('math.add', inputs: {'b': 25.0});
      final sSet = sub.addNode('var.set', properties: {'name': 'hp'});
      sub.connect(sStart.id, 'out', sSet.id, 'in');
      sub.connect(sGet.id, 'value', sAdd.id, 'a');
      sub.connect(sAdd.id, 'result', sSet.id, 'value');

      final root = FlowGraph(name: 'HeroLogic');
      root.blackboard.set('hp', 50);
      root.subgraphs['heal'] = sub;
      final rStart = root.addNode('event.start', x: 10, y: 20);
      final rSub = root.addNode(
        'graph.subgraph',
        x: 240,
        y: 20,
        properties: {'subgraphId': 'heal'},
      );
      root.connect(rStart.id, 'out', rSub.id, 'in');

      final jsonMap = root.toJson();
      final restored = FlowGraph.fromJson(jsonMap);
      expect(restored.getNode(rSub.id)!.x, 240);

      final runner = FlowRunner(restored);
      runner.triggerStart();
      expect((runner.blackboard.get('hp') as num).toDouble(), closeTo(75.0, 1e-6));
    });
  });
}
