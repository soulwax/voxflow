import 'blackboard.dart';
import 'graph.dart';
import 'node.dart';
import 'types.dart';

/// Diagnostic snapshot recorded while executing a [FlowGraph].
final class FlowExecutionTrace {
  final List<String> executedNodeIds = [];
  final List<String> logs = [];
  final List<(String signal, Object? payload)> signals = [];
  final Map<String, Object?> lastPinValues = {};

  void clear() {
    executedNodeIds.clear();
    logs.clear();
    signals.clear();
    lastPinValues.clear();
  }
}

final class _PendingDelay {
  double remainingSeconds;
  final String fromNodeId;
  final String outExecPinId;

  _PendingDelay({
    required this.remainingSeconds,
    required this.fromNodeId,
    required this.outExecPinId,
  });
}

/// Pure-pull reactive dataflow evaluator with per-pass memoization and cycle guards.
final class DataflowEvaluator {
  final FlowGraph graph;
  final FlowBlackboard blackboard;
  final Object? userContext;

  final Map<String, Map<String, Object?>> _pureCache = {};
  final Set<String> _visiting = {};

  DataflowEvaluator(
    this.graph, {
    FlowBlackboard? blackboard,
    this.userContext,
  }) : blackboard = blackboard ?? graph.blackboard;

  void invalidateCache() => _pureCache.clear();

  /// Pulls and coerces the output value of ([nodeId], [outputPinId]).
  Object? evaluateOutput(
    String nodeId,
    String outputPinId, {
    double dt = 0.0,
    bool freshPass = true,
  }) {
    if (freshPass) {
      _pureCache.clear();
    }
    return _pullNodeOutput(nodeId, outputPinId, dt, null);
  }

  Object? _pullNodeOutput(
    String nodeId,
    String outputPinId,
    double dt,
    Map<String, Map<String, Object?>>? runtimeNodeOutputs,
  ) {
    final cachedMap = _pureCache[nodeId];
    if (cachedMap != null && cachedMap.containsKey(outputPinId)) {
      return cachedMap[outputPinId];
    }
    final runtimeMap = runtimeNodeOutputs?[nodeId];
    if (runtimeMap != null && runtimeMap.containsKey(outputPinId)) {
      return runtimeMap[outputPinId];
    }

    final node = graph.getNode(nodeId);
    final def = graph.getNodeDef(nodeId);
    if (node == null || def == null) return null;

    if (!def.isPure) {
      // Non-pure node outputs live in runtimeNodeOutputs populated when executed.
      return runtimeMap?[outputPinId];
    }

    if (!_visiting.add(nodeId)) {
      throw StateError('Cycle detected while evaluating pure node "$nodeId"');
    }

    try {
      final outMap = _pureCache.putIfAbsent(nodeId, () => {});
      final ctx = _PullNodeContext(
        evaluator: this,
        node: node,
        def: def,
        dt: dt,
        outTarget: outMap,
        runtimeNodeOutputs: runtimeNodeOutputs,
      );
      def.evaluate?.call(ctx);
      return outMap[outputPinId];
    } finally {
      _visiting.remove(nodeId);
    }
  }

  Object? _resolveInputPin(
    FlowNodeInstance node,
    FlowNodeDef def,
    String pinId,
    double dt,
    Map<String, Map<String, Object?>>? runtimeNodeOutputs,
  ) {
    final pin = def.findPin(pinId, PinDirection.input);
    final targetType = pin?.type ?? PinType.any;

    final link = graph.findIncomingDataLink(node.id, pinId);
    Object? raw;
    if (link != null) {
      raw = _pullNodeOutput(
        link.fromNodeId,
        link.fromPinId,
        dt,
        runtimeNodeOutputs,
      );
    } else if (node.inputOverrides.containsKey(pinId)) {
      raw = node.inputOverrides[pinId];
    } else {
      raw = pin?.defaultValue;
    }

    return PinTypeCompatibility.coerce(raw, targetType);
  }
}

final class _PullNodeContext implements FlowNodeContext {
  final DataflowEvaluator evaluator;
  @override
  final FlowNodeInstance node;
  final FlowNodeDef def;
  @override
  final double dt;
  final Map<String, Object?> outTarget;
  final Map<String, Map<String, Object?>>? runtimeNodeOutputs;

  _PullNodeContext({
    required this.evaluator,
    required this.node,
    required this.def,
    required this.dt,
    required this.outTarget,
    required this.runtimeNodeOutputs,
  });

  @override
  FlowBlackboard get blackboard => evaluator.blackboard;

  @override
  Object? get userContext => evaluator.userContext;

  @override
  Object? readRaw(String pinId) =>
      evaluator._resolveInputPin(node, def, pinId, dt, runtimeNodeOutputs);

  @override
  bool readBool(String pinId) => PinTypeCompatibility.toBool(readRaw(pinId));

  @override
  int readInt(String pinId) => PinTypeCompatibility.toInt(readRaw(pinId));

  @override
  double readFloat(String pinId) => PinTypeCompatibility.toDouble(readRaw(pinId));

  @override
  FlowVec2 readVec2(String pinId) => PinTypeCompatibility.toVec2(readRaw(pinId));

  @override
  FlowVec3 readVec3(String pinId) => PinTypeCompatibility.toVec3(readRaw(pinId));

  @override
  String readString(String pinId) => (readRaw(pinId) ?? '').toString();

  @override
  FlowColor readColor(String pinId) => PinTypeCompatibility.toColor(readRaw(pinId));

  @override
  T? getMemory<T>(String key) => null;

  @override
  void setMemory(String key, Object? value) {}

  @override
  void writeOutput(String pinId, Object? value) {
    outTarget[pinId] = value;
  }

  @override
  T getProperty<T>(String key, T fallback) {
    final val = node.properties[key];
    return val is T ? val : fallback;
  }

  @override
  void invokeExec(String outExecPinId) {}

  @override
  void scheduleDelay(double seconds, String outExecPinId) {}

  @override
  void executeSubgraph(String subgraphId, {String eventName = 'OnStart'}) {}

  @override
  void log(String message) {}

  @override
  void emitSignal(String signalName, [Object? payload]) {}
}

/// Event-driven & latent Blueprint runtime executing a [FlowGraph].
final class FlowRunner {
  final FlowGraph graph;
  final FlowBlackboard blackboard;
  final Object? userContext;
  final int maxStepsPerTrigger;
  final FlowExecutionTrace trace = FlowExecutionTrace();

  void Function(String message)? onLog;
  void Function(String signalName, Object? payload)? onSignal;

  late final DataflowEvaluator _dataEvaluator = DataflowEvaluator(
    graph,
    blackboard: blackboard,
    userContext: userContext,
  );

  final Map<String, Map<String, Object?>> _nodeOutputs = {};
  final Map<String, Map<String, Object?>> _nodeMemory = {};
  final List<_PendingDelay> _pendingDelays = [];
  final Map<String, FlowRunner> _subgraphRunners = {};

  int _stepBudget = 0;

  FlowRunner(
    this.graph, {
    FlowBlackboard? blackboard,
    this.userContext,
    this.maxStepsPerTrigger = 2048,
    this.onLog,
    this.onSignal,
  }) : blackboard = blackboard ?? graph.blackboard;

  int get activeDelayCount => _pendingDelays.length;

  /// Evaluates any pure data output pin directly without running exec chains.
  Object? evaluateOutput(String nodeId, String outputPinId, {double dt = 0.0}) =>
      _dataEvaluator.evaluateOutput(nodeId, outputPinId, dt: dt, freshPass: true);

  /// Executes all `event.start` entry nodes in the graph.
  void triggerStart() {
    _dataEvaluator.invalidateCache();
    for (final node in graph.nodes.values) {
      if (node.typeId == 'event.start') {
        _stepBudget = maxStepsPerTrigger;
        _executeNode(node.id, 'in', 0.0);
      }
    }
  }

  /// Advances active latent timers (`Delay`) and fires all `event.update` entry nodes.
  void step(double dt) {
    _dataEvaluator.invalidateCache();

    // Tick pending delays safely using a snapshot of matured entries.
    if (_pendingDelays.isNotEmpty) {
      final stillWaiting = <_PendingDelay>[];
      final ready = <_PendingDelay>[];
      for (final d in _pendingDelays) {
        d.remainingSeconds -= dt;
        if (d.remainingSeconds <= 1e-9) {
          ready.add(d);
        } else {
          stillWaiting.add(d);
        }
      }
      _pendingDelays
        ..clear()
        ..addAll(stillWaiting);

      for (final r in ready) {
        _stepBudget = maxStepsPerTrigger;
        _followExecPin(r.fromNodeId, r.outExecPinId, dt);
      }
    }

    for (final sub in _subgraphRunners.values) {
      sub.step(dt);
    }

    for (final node in graph.nodes.values) {
      if (node.typeId == 'event.update') {
        _stepBudget = maxStepsPerTrigger;
        _executeNode(node.id, 'in', dt);
      }
    }
  }

  /// Fires all `event.custom` nodes whose `properties['event'] == eventName`.
  void triggerEvent(String eventName, {Object? payload, double dt = 0.0}) {
    _dataEvaluator.invalidateCache();
    for (final node in graph.nodes.values) {
      if (node.typeId == 'event.custom') {
        final target = (node.properties['event'] as String?) ?? '';
        if (target == eventName) {
          _nodeOutputs.putIfAbsent(node.id, () => {})['payload'] = payload;
          trace.lastPinValues['${node.id}.payload'] = payload;
          _stepBudget = maxStepsPerTrigger;
          _executeNode(node.id, 'in', dt);
        }
      }
    }
  }

  void resetRuntimeState() {
    _nodeOutputs.clear();
    _nodeMemory.clear();
    _pendingDelays.clear();
    _subgraphRunners.clear();
    _dataEvaluator.invalidateCache();
    trace.clear();
  }

  void _executeNode(String nodeId, String inExecPin, double dt) {
    if (_stepBudget-- <= 0) {
      throw StateError(
        'FlowRunner exceeded maxStepsPerTrigger ($maxStepsPerTrigger) in graph "${graph.name}"',
      );
    }

    final node = graph.getNode(nodeId);
    final def = graph.getNodeDef(nodeId);
    if (node == null || def == null) return;

    trace.executedNodeIds.add(nodeId);
    final outMap = _nodeOutputs.putIfAbsent(nodeId, () => {});
    final memMap = _nodeMemory.putIfAbsent(nodeId, () => {});

    final ctx = _ExecNodeContext(
      runner: this,
      node: node,
      def: def,
      dt: dt,
      outTarget: outMap,
      memory: memMap,
    );

    if (def.execute != null) {
      def.execute!(ctx, inExecPin);
    } else if (def.evaluate != null) {
      def.evaluate!(ctx);
    }

    // Record live output values for UI/debugger inspection.
    for (final entry in outMap.entries) {
      trace.lastPinValues['$nodeId.${entry.key}'] = entry.value;
    }
    // Imperative execution may mutate blackboard or scene state, so invalidate
    // pure pull caches to keep subsequent downstream reads consistent.
    _dataEvaluator.invalidateCache();
  }

  void _followExecPin(String fromNodeId, String outExecPinId, double dt) {
    final links = graph.findOutgoingExecLinks(fromNodeId, outExecPinId);
    for (final link in links) {
      _executeNode(link.toNodeId, link.toPinId, dt);
    }
  }

  void _executeSubgraph(String subgraphId, String eventName, double dt) {
    final subGraph = graph.subgraphs[subgraphId];
    if (subGraph == null) {
      throw ArgumentError('Subgraph "$subgraphId" not found in "${graph.name}"');
    }
    final subRunner = _subgraphRunners.putIfAbsent(
      subgraphId,
      () => FlowRunner(
        subGraph,
        blackboard: blackboard,
        userContext: userContext,
        maxStepsPerTrigger: maxStepsPerTrigger,
        onLog: onLog,
        onSignal: onSignal,
      ),
    );
    if (eventName == 'OnStart') {
      subRunner.triggerStart();
    } else {
      subRunner.triggerEvent(eventName, dt: dt);
    }
  }
}

final class _ExecNodeContext implements FlowNodeContext {
  final FlowRunner runner;
  @override
  final FlowNodeInstance node;
  final FlowNodeDef def;
  @override
  final double dt;
  final Map<String, Object?> outTarget;
  final Map<String, Object?> memory;

  _ExecNodeContext({
    required this.runner,
    required this.node,
    required this.def,
    required this.dt,
    required this.outTarget,
    required this.memory,
  });

  @override
  FlowBlackboard get blackboard => runner.blackboard;

  @override
  Object? get userContext => runner.userContext;

  @override
  Object? readRaw(String pinId) {
    final val = runner._dataEvaluator._resolveInputPin(
      node,
      def,
      pinId,
      dt,
      runner._nodeOutputs,
    );
    runner.trace.lastPinValues['${node.id}.$pinId'] = val;
    return val;
  }

  @override
  bool readBool(String pinId) => PinTypeCompatibility.toBool(readRaw(pinId));

  @override
  int readInt(String pinId) => PinTypeCompatibility.toInt(readRaw(pinId));

  @override
  double readFloat(String pinId) => PinTypeCompatibility.toDouble(readRaw(pinId));

  @override
  FlowVec2 readVec2(String pinId) => PinTypeCompatibility.toVec2(readRaw(pinId));

  @override
  FlowVec3 readVec3(String pinId) => PinTypeCompatibility.toVec3(readRaw(pinId));

  @override
  String readString(String pinId) => (readRaw(pinId) ?? '').toString();

  @override
  FlowColor readColor(String pinId) => PinTypeCompatibility.toColor(readRaw(pinId));

  @override
  T? getMemory<T>(String key) {
    final val = memory[key];
    return val is T ? val : null;
  }

  @override
  void setMemory(String key, Object? value) {
    memory[key] = value;
  }

  @override
  void writeOutput(String pinId, Object? value) {
    outTarget[pinId] = value;
    runner.trace.lastPinValues['${node.id}.$pinId'] = value;
  }

  @override
  T getProperty<T>(String key, T fallback) {
    final val = node.properties[key];
    return val is T ? val : fallback;
  }

  @override
  void invokeExec(String outExecPinId) {
    runner._followExecPin(node.id, outExecPinId, dt);
  }

  @override
  void scheduleDelay(double seconds, String outExecPinId) {
    runner._pendingDelays.add(
      _PendingDelay(
        remainingSeconds: seconds,
        fromNodeId: node.id,
        outExecPinId: outExecPinId,
      ),
    );
  }

  @override
  void executeSubgraph(String subgraphId, {String eventName = 'OnStart'}) {
    runner._executeSubgraph(subgraphId, eventName, dt);
  }

  @override
  void log(String message) {
    runner.trace.logs.add(message);
    runner.onLog?.call(message);
  }

  @override
  void emitSignal(String signalName, [Object? payload]) {
    runner.trace.signals.add((signalName, payload));
    runner.onSignal?.call(signalName, payload);
  }
}
