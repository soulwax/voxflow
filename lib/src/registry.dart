import 'dart:math' as math;

import 'node.dart';
import 'types.dart';

/// Registry of available node definitions for a [FlowGraph] and its runner.
final class FlowNodeRegistry {
  final Map<String, FlowNodeDef> _defs = {};

  FlowNodeRegistry({bool includeStandardNodes = true}) {
    if (includeStandardNodes) {
      StandardNodes.registerAll(this);
    }
  }

  void register(FlowNodeDef def) {
    _defs[def.typeId] = def;
  }

  void registerAll(Iterable<FlowNodeDef> defs) {
    for (final d in defs) {
      register(d);
    }
  }

  FlowNodeDef? get(String typeId) => _defs[typeId];
  bool contains(String typeId) => _defs.containsKey(typeId);
  Iterable<FlowNodeDef> get all => _defs.values;

  List<FlowNodeDef> byCategory(String category) =>
      _defs.values.where((d) => d.category == category).toList(growable: false);

  List<String> get categories {
    final cats = _defs.values.map((d) => d.category).toSet().toList()..sort();
    return cats;
  }

  FlowNodeRegistry clone() {
    final copy = FlowNodeRegistry(includeStandardNodes: false);
    copy.registerAll(_defs.values);
    return copy;
  }
}

/// Built-in catalog of events, flow control, math, logic, vector, color, variable, and subgraph nodes.
abstract final class StandardNodes {
  static final _rng = math.Random();

  static void registerAll(FlowNodeRegistry registry) {
    registry.registerAll([
      // --- Events ---
      FlowNodeDef(
        typeId: 'event.start',
        title: 'On Start',
        category: 'Events',
        isPure: false,
        isEventEntry: true,
        inputs: const [],
        outputs: const [PinDef.execOut('out', 'Out')],
        execute: (ctx, _) => ctx.invokeExec('out'),
      ),
      FlowNodeDef(
        typeId: 'event.update',
        title: 'On Update',
        category: 'Events',
        isPure: false,
        isEventEntry: true,
        inputs: const [],
        outputs: const [
          PinDef.execOut('out', 'Out'),
          PinDef.output('dt', 'Delta Time', PinType.floatVal),
        ],
        execute: (ctx, _) {
          ctx.writeOutput('dt', ctx.dt);
          ctx.invokeExec('out');
        },
      ),
      FlowNodeDef(
        typeId: 'event.custom',
        title: 'On Event',
        category: 'Events',
        isPure: false,
        isEventEntry: true,
        inputs: const [],
        outputs: const [
          PinDef.execOut('out', 'Out'),
          PinDef.output('payload', 'Payload', PinType.any),
        ],
        execute: (ctx, _) => ctx.invokeExec('out'),
      ),

      // --- Flow Control ---
      FlowNodeDef(
        typeId: 'flow.branch',
        title: 'Branch',
        category: 'Flow',
        isPure: false,
        inputs: const [
          PinDef.execIn(),
          PinDef.input('condition', 'Condition', PinType.boolVal, defaultValue: false),
        ],
        outputs: const [
          PinDef.execOut('true', 'True'),
          PinDef.execOut('false', 'False'),
        ],
        execute: (ctx, _) {
          final cond = ctx.readBool('condition');
          ctx.invokeExec(cond ? 'true' : 'false');
        },
      ),
      FlowNodeDef(
        typeId: 'flow.sequence',
        title: 'Sequence',
        category: 'Flow',
        isPure: false,
        inputs: const [PinDef.execIn()],
        outputs: const [
          PinDef.execOut('then0', 'Then 0'),
          PinDef.execOut('then1', 'Then 1'),
          PinDef.execOut('then2', 'Then 2'),
        ],
        execute: (ctx, _) {
          ctx.invokeExec('then0');
          ctx.invokeExec('then1');
          ctx.invokeExec('then2');
        },
      ),
      FlowNodeDef(
        typeId: 'flow.forLoop',
        title: 'For Loop',
        category: 'Flow',
        isPure: false,
        inputs: const [
          PinDef.execIn(),
          PinDef.input('firstIndex', 'First Index', PinType.intVal, defaultValue: 0),
          PinDef.input('lastIndex', 'Last Index', PinType.intVal, defaultValue: 3),
        ],
        outputs: const [
          PinDef.execOut('loopBody', 'Loop Body'),
          PinDef.output('index', 'Index', PinType.intVal),
          PinDef.execOut('completed', 'Completed'),
        ],
        execute: (ctx, _) {
          final start = ctx.readInt('firstIndex');
          final end = ctx.readInt('lastIndex');
          for (var i = start; i <= end; i++) {
            ctx.writeOutput('index', i);
            ctx.invokeExec('loopBody');
          }
          ctx.invokeExec('completed');
        },
      ),
      FlowNodeDef(
        typeId: 'flow.delay',
        title: 'Delay',
        category: 'Flow',
        isPure: false,
        inputs: const [
          PinDef.execIn(),
          PinDef.input('seconds', 'Seconds', PinType.floatVal, defaultValue: 1.0),
        ],
        outputs: const [PinDef.execOut('completed', 'Completed')],
        execute: (ctx, _) {
          final sec = math.max(0.0, ctx.readFloat('seconds'));
          if (sec == 0.0) {
            ctx.invokeExec('completed');
          } else {
            ctx.scheduleDelay(sec, 'completed');
          }
        },
      ),
      FlowNodeDef(
        typeId: 'flow.doOnce',
        title: 'Do Once',
        category: 'Flow',
        isPure: false,
        inputs: const [
          PinDef.execIn('in', 'In'),
          PinDef.execIn('reset', 'Reset'),
        ],
        outputs: const [PinDef.execOut('completed', 'Completed')],
        execute: (ctx, inPin) {
          if (inPin == 'reset') {
            ctx.setMemory('fired', false);
            return;
          }
          final fired = ctx.getMemory<bool>('fired') ?? false;
          if (!fired) {
            ctx.setMemory('fired', true);
            ctx.invokeExec('completed');
          }
        },
      ),

      // --- Constants ---
      FlowNodeDef(
        typeId: 'math.constFloat',
        title: 'Float',
        category: 'Constants',
        inputs: const [],
        outputs: const [PinDef.output('value', 'Value', PinType.floatVal)],
        evaluate: (ctx) => ctx.writeOutput('value', (ctx.getProperty<num>('value', 0.0)).toDouble()),
      ),
      FlowNodeDef(
        typeId: 'math.constInt',
        title: 'Integer',
        category: 'Constants',
        inputs: const [],
        outputs: const [PinDef.output('value', 'Value', PinType.intVal)],
        evaluate: (ctx) => ctx.writeOutput('value', ctx.getProperty<num>('value', 0).round()),
      ),
      FlowNodeDef(
        typeId: 'math.constBool',
        title: 'Boolean',
        category: 'Constants',
        inputs: const [],
        outputs: const [PinDef.output('value', 'Value', PinType.boolVal)],
        evaluate: (ctx) => ctx.writeOutput('value', ctx.getProperty<bool>('value', false)),
      ),
      FlowNodeDef(
        typeId: 'math.constString',
        title: 'String',
        category: 'Constants',
        inputs: const [],
        outputs: const [PinDef.output('value', 'Value', PinType.stringVal)],
        evaluate: (ctx) => ctx.writeOutput('value', ctx.getProperty<String>('value', '')),
      ),

      // --- Math ---
      FlowNodeDef(
        typeId: 'math.add',
        title: 'Add',
        category: 'Math',
        inputs: const [
          PinDef.input('a', 'A', PinType.floatVal, defaultValue: 0.0),
          PinDef.input('b', 'B', PinType.floatVal, defaultValue: 0.0),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.floatVal)],
        evaluate: (ctx) => ctx.writeOutput('result', ctx.readFloat('a') + ctx.readFloat('b')),
      ),
      FlowNodeDef(
        typeId: 'math.sub',
        title: 'Subtract',
        category: 'Math',
        inputs: const [
          PinDef.input('a', 'A', PinType.floatVal, defaultValue: 0.0),
          PinDef.input('b', 'B', PinType.floatVal, defaultValue: 0.0),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.floatVal)],
        evaluate: (ctx) => ctx.writeOutput('result', ctx.readFloat('a') - ctx.readFloat('b')),
      ),
      FlowNodeDef(
        typeId: 'math.mul',
        title: 'Multiply',
        category: 'Math',
        inputs: const [
          PinDef.input('a', 'A', PinType.floatVal, defaultValue: 1.0),
          PinDef.input('b', 'B', PinType.floatVal, defaultValue: 1.0),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.floatVal)],
        evaluate: (ctx) => ctx.writeOutput('result', ctx.readFloat('a') * ctx.readFloat('b')),
      ),
      FlowNodeDef(
        typeId: 'math.div',
        title: 'Divide',
        category: 'Math',
        inputs: const [
          PinDef.input('a', 'A', PinType.floatVal, defaultValue: 0.0),
          PinDef.input('b', 'B', PinType.floatVal, defaultValue: 1.0),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.floatVal)],
        evaluate: (ctx) {
          final denom = ctx.readFloat('b');
          ctx.writeOutput('result', denom.abs() < 1e-12 ? 0.0 : ctx.readFloat('a') / denom);
        },
      ),
      FlowNodeDef(
        typeId: 'math.clamp',
        title: 'Clamp',
        category: 'Math',
        inputs: const [
          PinDef.input('value', 'Value', PinType.floatVal, defaultValue: 0.0),
          PinDef.input('min', 'Min', PinType.floatVal, defaultValue: 0.0),
          PinDef.input('max', 'Max', PinType.floatVal, defaultValue: 1.0),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.floatVal)],
        evaluate: (ctx) {
          final v = ctx.readFloat('value');
          final mn = ctx.readFloat('min');
          final mx = ctx.readFloat('max');
          final lo = math.min(mn, mx);
          final hi = math.max(mn, mx);
          ctx.writeOutput('result', v.clamp(lo, hi).toDouble());
        },
      ),
      FlowNodeDef(
        typeId: 'math.lerp',
        title: 'Lerp',
        category: 'Math',
        inputs: const [
          PinDef.input('a', 'A', PinType.floatVal, defaultValue: 0.0),
          PinDef.input('b', 'B', PinType.floatVal, defaultValue: 1.0),
          PinDef.input('t', 'Alpha', PinType.floatVal, defaultValue: 0.5),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.floatVal)],
        evaluate: (ctx) {
          final a = ctx.readFloat('a');
          final b = ctx.readFloat('b');
          final t = ctx.readFloat('t');
          ctx.writeOutput('result', a + (b - a) * t);
        },
      ),
      FlowNodeDef(
        typeId: 'math.remap',
        title: 'Remap Range',
        category: 'Math',
        inputs: const [
          PinDef.input('value', 'Value', PinType.floatVal, defaultValue: 0.5),
          PinDef.input('inMin', 'In Min', PinType.floatVal, defaultValue: 0.0),
          PinDef.input('inMax', 'In Max', PinType.floatVal, defaultValue: 1.0),
          PinDef.input('outMin', 'Out Min', PinType.floatVal, defaultValue: 0.0),
          PinDef.input('outMax', 'Out Max', PinType.floatVal, defaultValue: 100.0),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.floatVal)],
        evaluate: (ctx) {
          final v = ctx.readFloat('value');
          final i0 = ctx.readFloat('inMin');
          final i1 = ctx.readFloat('inMax');
          final o0 = ctx.readFloat('outMin');
          final o1 = ctx.readFloat('outMax');
          final span = i1 - i0;
          final t = span.abs() < 1e-12 ? 0.0 : (v - i0) / span;
          ctx.writeOutput('result', o0 + (o1 - o0) * t);
        },
      ),
      FlowNodeDef(
        typeId: 'math.sin',
        title: 'Sin',
        category: 'Math',
        inputs: const [PinDef.input('x', 'Radians', PinType.floatVal, defaultValue: 0.0)],
        outputs: const [PinDef.output('result', 'Result', PinType.floatVal)],
        evaluate: (ctx) => ctx.writeOutput('result', math.sin(ctx.readFloat('x'))),
      ),
      FlowNodeDef(
        typeId: 'math.cos',
        title: 'Cos',
        category: 'Math',
        inputs: const [PinDef.input('x', 'Radians', PinType.floatVal, defaultValue: 0.0)],
        outputs: const [PinDef.output('result', 'Result', PinType.floatVal)],
        evaluate: (ctx) => ctx.writeOutput('result', math.cos(ctx.readFloat('x'))),
      ),
      FlowNodeDef(
        typeId: 'math.abs',
        title: 'Abs',
        category: 'Math',
        inputs: const [PinDef.input('x', 'X', PinType.floatVal, defaultValue: 0.0)],
        outputs: const [PinDef.output('result', 'Result', PinType.floatVal)],
        evaluate: (ctx) => ctx.writeOutput('result', ctx.readFloat('x').abs()),
      ),
      FlowNodeDef(
        typeId: 'math.min',
        title: 'Min',
        category: 'Math',
        inputs: const [
          PinDef.input('a', 'A', PinType.floatVal, defaultValue: 0.0),
          PinDef.input('b', 'B', PinType.floatVal, defaultValue: 0.0),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.floatVal)],
        evaluate: (ctx) => ctx.writeOutput('result', math.min(ctx.readFloat('a'), ctx.readFloat('b'))),
      ),
      FlowNodeDef(
        typeId: 'math.max',
        title: 'Max',
        category: 'Math',
        inputs: const [
          PinDef.input('a', 'A', PinType.floatVal, defaultValue: 0.0),
          PinDef.input('b', 'B', PinType.floatVal, defaultValue: 0.0),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.floatVal)],
        evaluate: (ctx) => ctx.writeOutput('result', math.max(ctx.readFloat('a'), ctx.readFloat('b'))),
      ),
      FlowNodeDef(
        typeId: 'math.randomRange',
        title: 'Random Range',
        category: 'Math',
        inputs: const [
          PinDef.input('min', 'Min', PinType.floatVal, defaultValue: 0.0),
          PinDef.input('max', 'Max', PinType.floatVal, defaultValue: 1.0),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.floatVal)],
        evaluate: (ctx) {
          final mn = ctx.readFloat('min');
          final mx = ctx.readFloat('max');
          ctx.writeOutput('result', mn + _rng.nextDouble() * (mx - mn));
        },
      ),

      // --- Logic & Comparison ---
      FlowNodeDef(
        typeId: 'logic.compare',
        title: 'Compare',
        category: 'Logic',
        inputs: const [
          PinDef.input('a', 'A', PinType.floatVal, defaultValue: 0.0),
          PinDef.input('b', 'B', PinType.floatVal, defaultValue: 0.0),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.boolVal)],
        evaluate: (ctx) {
          final a = ctx.readFloat('a');
          final b = ctx.readFloat('b');
          final op = ctx.getProperty<String>('op', '==');
          final res = switch (op) {
            '==' => (a - b).abs() < 1e-6,
            '!=' => (a - b).abs() >= 1e-6,
            '<' => a < b,
            '<=' => a <= b,
            '>' => a > b,
            '>=' => a >= b,
            _ => a == b,
          };
          ctx.writeOutput('result', res);
        },
      ),
      FlowNodeDef(
        typeId: 'logic.and',
        title: 'AND',
        category: 'Logic',
        inputs: const [
          PinDef.input('a', 'A', PinType.boolVal, defaultValue: false),
          PinDef.input('b', 'B', PinType.boolVal, defaultValue: false),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.boolVal)],
        evaluate: (ctx) => ctx.writeOutput('result', ctx.readBool('a') && ctx.readBool('b')),
      ),
      FlowNodeDef(
        typeId: 'logic.or',
        title: 'OR',
        category: 'Logic',
        inputs: const [
          PinDef.input('a', 'A', PinType.boolVal, defaultValue: false),
          PinDef.input('b', 'B', PinType.boolVal, defaultValue: false),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.boolVal)],
        evaluate: (ctx) => ctx.writeOutput('result', ctx.readBool('a') || ctx.readBool('b')),
      ),
      FlowNodeDef(
        typeId: 'logic.not',
        title: 'NOT',
        category: 'Logic',
        inputs: const [PinDef.input('a', 'A', PinType.boolVal, defaultValue: false)],
        outputs: const [PinDef.output('result', 'Result', PinType.boolVal)],
        evaluate: (ctx) => ctx.writeOutput('result', !ctx.readBool('a')),
      ),
      FlowNodeDef(
        typeId: 'logic.select',
        title: 'Select',
        category: 'Logic',
        inputs: const [
          PinDef.input('pick', 'Pick A', PinType.boolVal, defaultValue: true),
          PinDef.input('a', 'True Val', PinType.any),
          PinDef.input('b', 'False Val', PinType.any),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.any)],
        evaluate: (ctx) =>
            ctx.writeOutput('result', ctx.readBool('pick') ? ctx.readRaw('a') : ctx.readRaw('b')),
      ),

      // --- Vectors & Color ---
      FlowNodeDef(
        typeId: 'vec.make2',
        title: 'Make Vec2',
        category: 'Vector',
        inputs: const [
          PinDef.input('x', 'X', PinType.floatVal, defaultValue: 0.0),
          PinDef.input('y', 'Y', PinType.floatVal, defaultValue: 0.0),
        ],
        outputs: const [PinDef.output('vec', 'Vec2', PinType.vec2Val)],
        evaluate: (ctx) => ctx.writeOutput('vec', FlowVec2(ctx.readFloat('x'), ctx.readFloat('y'))),
      ),
      FlowNodeDef(
        typeId: 'vec.break2',
        title: 'Break Vec2',
        category: 'Vector',
        inputs: const [PinDef.input('vec', 'Vec2', PinType.vec2Val)],
        outputs: const [
          PinDef.output('x', 'X', PinType.floatVal),
          PinDef.output('y', 'Y', PinType.floatVal),
        ],
        evaluate: (ctx) {
          final v = ctx.readVec2('vec');
          ctx.writeOutput('x', v.x);
          ctx.writeOutput('y', v.y);
        },
      ),
      FlowNodeDef(
        typeId: 'vec.make3',
        title: 'Make Vec3',
        category: 'Vector',
        inputs: const [
          PinDef.input('x', 'X', PinType.floatVal, defaultValue: 0.0),
          PinDef.input('y', 'Y', PinType.floatVal, defaultValue: 0.0),
          PinDef.input('z', 'Z', PinType.floatVal, defaultValue: 0.0),
        ],
        outputs: const [PinDef.output('vec', 'Vec3', PinType.vec3Val)],
        evaluate: (ctx) => ctx.writeOutput(
          'vec',
          FlowVec3(ctx.readFloat('x'), ctx.readFloat('y'), ctx.readFloat('z')),
        ),
      ),
      FlowNodeDef(
        typeId: 'vec.break3',
        title: 'Break Vec3',
        category: 'Vector',
        inputs: const [PinDef.input('vec', 'Vec3', PinType.vec3Val)],
        outputs: const [
          PinDef.output('x', 'X', PinType.floatVal),
          PinDef.output('y', 'Y', PinType.floatVal),
          PinDef.output('z', 'Z', PinType.floatVal),
        ],
        evaluate: (ctx) {
          final v = ctx.readVec3('vec');
          ctx.writeOutput('x', v.x);
          ctx.writeOutput('y', v.y);
          ctx.writeOutput('z', v.z);
        },
      ),
      FlowNodeDef(
        typeId: 'vec.add3',
        title: 'Add Vec3',
        category: 'Vector',
        inputs: const [
          PinDef.input('a', 'A', PinType.vec3Val),
          PinDef.input('b', 'B', PinType.vec3Val),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.vec3Val)],
        evaluate: (ctx) => ctx.writeOutput('result', ctx.readVec3('a') + ctx.readVec3('b')),
      ),
      FlowNodeDef(
        typeId: 'vec.scale3',
        title: 'Scale Vec3',
        category: 'Vector',
        inputs: const [
          PinDef.input('v', 'Vector', PinType.vec3Val),
          PinDef.input('s', 'Scale', PinType.floatVal, defaultValue: 1.0),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.vec3Val)],
        evaluate: (ctx) => ctx.writeOutput('result', ctx.readVec3('v') * ctx.readFloat('s')),
      ),
      FlowNodeDef(
        typeId: 'vec.length3',
        title: 'Vec3 Length',
        category: 'Vector',
        inputs: const [PinDef.input('v', 'Vector', PinType.vec3Val)],
        outputs: const [PinDef.output('length', 'Length', PinType.floatVal)],
        evaluate: (ctx) => ctx.writeOutput('length', ctx.readVec3('v').length),
      ),
      FlowNodeDef(
        typeId: 'vec.normalize3',
        title: 'Normalize Vec3',
        category: 'Vector',
        inputs: const [PinDef.input('v', 'Vector', PinType.vec3Val)],
        outputs: const [PinDef.output('result', 'Normalized', PinType.vec3Val)],
        evaluate: (ctx) => ctx.writeOutput('result', ctx.readVec3('v').normalized()),
      ),
      FlowNodeDef(
        typeId: 'vec.lerp3',
        title: 'Lerp Vec3',
        category: 'Vector',
        inputs: const [
          PinDef.input('a', 'A', PinType.vec3Val),
          PinDef.input('b', 'B', PinType.vec3Val),
          PinDef.input('t', 'Alpha', PinType.floatVal, defaultValue: 0.5),
        ],
        outputs: const [PinDef.output('result', 'Result', PinType.vec3Val)],
        evaluate: (ctx) => ctx.writeOutput(
          'result',
          FlowVec3.lerp(ctx.readVec3('a'), ctx.readVec3('b'), ctx.readFloat('t')),
        ),
      ),
      FlowNodeDef(
        typeId: 'color.make',
        title: 'Make Color',
        category: 'Color',
        inputs: const [
          PinDef.input('r', 'R', PinType.floatVal, defaultValue: 1.0),
          PinDef.input('g', 'G', PinType.floatVal, defaultValue: 1.0),
          PinDef.input('b', 'B', PinType.floatVal, defaultValue: 1.0),
          PinDef.input('a', 'A', PinType.floatVal, defaultValue: 1.0),
        ],
        outputs: const [PinDef.output('color', 'Color', PinType.colorVal)],
        evaluate: (ctx) => ctx.writeOutput(
          'color',
          FlowColor(
            ctx.readFloat('r'),
            ctx.readFloat('g'),
            ctx.readFloat('b'),
            ctx.readFloat('a'),
          ),
        ),
      ),
      FlowNodeDef(
        typeId: 'color.lerp',
        title: 'Lerp Color',
        category: 'Color',
        inputs: const [
          PinDef.input('a', 'A', PinType.colorVal),
          PinDef.input('b', 'B', PinType.colorVal),
          PinDef.input('t', 'Alpha', PinType.floatVal, defaultValue: 0.5),
        ],
        outputs: const [PinDef.output('color', 'Color', PinType.colorVal)],
        evaluate: (ctx) => ctx.writeOutput(
          'color',
          FlowColor.lerp(ctx.readColor('a'), ctx.readColor('b'), ctx.readFloat('t')),
        ),
      ),

      // --- Variables, Signals, Debug, Subgraph ---
      FlowNodeDef(
        typeId: 'var.get',
        title: 'Get Variable',
        category: 'Variables',
        inputs: const [],
        outputs: const [PinDef.output('value', 'Value', PinType.any)],
        evaluate: (ctx) {
          final name = ctx.getProperty<String>('name', '');
          ctx.writeOutput('value', ctx.blackboard.get(name));
        },
      ),
      FlowNodeDef(
        typeId: 'var.set',
        title: 'Set Variable',
        category: 'Variables',
        isPure: false,
        inputs: const [
          PinDef.execIn(),
          PinDef.input('value', 'Value', PinType.any),
        ],
        outputs: const [
          PinDef.execOut('out', 'Out'),
          PinDef.output('value', 'Value', PinType.any),
        ],
        execute: (ctx, _) {
          final name = ctx.getProperty<String>('name', '');
          final v = ctx.readRaw('value');
          if (name.isNotEmpty) {
            ctx.blackboard.set(name, v);
          }
          ctx.writeOutput('value', v);
          ctx.invokeExec('out');
        },
      ),
      FlowNodeDef(
        typeId: 'debug.print',
        title: 'Print',
        category: 'Debug',
        isPure: false,
        inputs: const [
          PinDef.execIn(),
          PinDef.input('message', 'Message', PinType.stringVal, defaultValue: 'Hello'),
        ],
        outputs: const [PinDef.execOut()],
        execute: (ctx, _) {
          ctx.log(ctx.readString('message'));
          ctx.invokeExec('out');
        },
      ),
      FlowNodeDef(
        typeId: 'signal.emit',
        title: 'Emit Signal',
        category: 'Events',
        isPure: false,
        inputs: const [
          PinDef.execIn(),
          PinDef.input('payload', 'Payload', PinType.any),
        ],
        outputs: const [PinDef.execOut()],
        execute: (ctx, _) {
          final sig = ctx.getProperty<String>('signal', 'signal');
          ctx.emitSignal(sig, ctx.readRaw('payload'));
          ctx.invokeExec('out');
        },
      ),
      FlowNodeDef(
        typeId: 'graph.subgraph',
        title: 'Subgraph',
        category: 'Flow',
        isPure: false,
        inputs: const [PinDef.execIn()],
        outputs: const [PinDef.execOut()],
        execute: (ctx, _) {
          final sub = ctx.getProperty<String>('subgraphId', '');
          final evt = ctx.getProperty<String>('entryEvent', 'OnStart');
          if (sub.isNotEmpty) {
            ctx.executeSubgraph(sub, eventName: evt);
          }
          ctx.invokeExec('out');
        },
      ),
    ]);
  }
}
