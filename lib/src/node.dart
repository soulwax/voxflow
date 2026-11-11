import 'blackboard.dart';
import 'types.dart';

/// Descriptor for a single input or output pin on a [FlowNodeDef].
final class PinDef {
  final String id;
  final String label;
  final PinType type;
  final PinDirection direction;
  final Object? defaultValue;
  final bool allowMultipleConnections;

  const PinDef({
    required this.id,
    required this.label,
    required this.type,
    required this.direction,
    this.defaultValue,
    bool? allowMultipleConnections,
  }) : allowMultipleConnections = allowMultipleConnections ??
            (direction == PinDirection.output || type == PinType.exec);

  const PinDef.execIn([this.id = 'in', this.label = 'In'])
      : type = PinType.exec,
        direction = PinDirection.input,
        defaultValue = null,
        allowMultipleConnections = true;

  const PinDef.execOut([this.id = 'out', this.label = 'Out'])
      : type = PinType.exec,
        direction = PinDirection.output,
        defaultValue = null,
        allowMultipleConnections = false;

  const PinDef.input(
    this.id,
    this.label,
    this.type, {
    this.defaultValue,
  })  : direction = PinDirection.input,
        allowMultipleConnections = false;

  const PinDef.output(
    this.id,
    this.label,
    this.type, {
    this.allowMultipleConnections = true,
  })  : direction = PinDirection.output,
        defaultValue = null;
}

/// Execution / evaluation context passed to a node's evaluation and exec handlers.
abstract interface class FlowNodeContext {
  FlowNodeInstance get node;
  FlowBlackboard get blackboard;
  double get dt;
  Object? get userContext;

  /// Reads the coerced input value from [pinId] (pulling linked upstream data
  /// automatically or falling back to instance overrides / pin default).
  Object? readRaw(String pinId);
  bool readBool(String pinId);
  int readInt(String pinId);
  double readFloat(String pinId);
  FlowVec2 readVec2(String pinId);
  FlowVec3 readVec3(String pinId);
  String readString(String pinId);
  FlowColor readColor(String pinId);

  /// Stores a value into this node's local runtime memory across frames (e.g. DoOnce).
  T? getMemory<T>(String key);
  void setMemory(String key, Object? value);

  /// Assigns an output pin value during evaluation or execution.
  void writeOutput(String pinId, Object? value);

  /// Reads a property defined on [node.properties] (falls back to [fallback]).
  T getProperty<T>(String key, T fallback);

  /// Continues synchronous execution along the outgoing exec pin [outExecPinId].
  void invokeExec(String outExecPinId);

  /// Suspends this branch for [seconds], then resumes [outExecPinId] on future `step(dt)`.
  void scheduleDelay(double seconds, String outExecPinId);

  /// Runs a named embedded subgraph inside the owning graph.
  void executeSubgraph(String subgraphId, {String eventName = 'OnStart'});

  void log(String message);
  void emitSignal(String signalName, [Object? payload]);
}

/// Blueprint/Dataflow node template registered inside a [FlowNodeRegistry].
final class FlowNodeDef {
  final String typeId;
  final String title;
  final String category;

  /// Pure nodes have no `exec` pins and are evaluated lazily by downstream pull.
  final bool isPure;

  /// Event entry nodes (`OnStart`, `OnUpdate`, `OnEvent`) act as exec roots.
  final bool isEventEntry;

  final List<PinDef> inputs;
  final List<PinDef> outputs;

  final void Function(FlowNodeContext ctx)? evaluate;
  final void Function(FlowNodeContext ctx, String inExecPin)? execute;

  const FlowNodeDef({
    required this.typeId,
    required this.title,
    required this.category,
    required this.inputs,
    required this.outputs,
    this.isPure = true,
    this.isEventEntry = false,
    this.evaluate,
    this.execute,
  });

  PinDef? findPin(String pinId, [PinDirection? dir]) {
    if (dir == null || dir == PinDirection.input) {
      for (final p in inputs) {
        if (p.id == pinId) return p;
      }
    }
    if (dir == null || dir == PinDirection.output) {
      for (final p in outputs) {
        if (p.id == pinId) return p;
      }
    }
    return null;
  }
}

/// Concrete node placed inside a [FlowGraph], storing canvas position, inline literals,
/// and per-node properties (variable name, operator, constant values, comment).
final class FlowNodeInstance {
  final String id;
  final String typeId;
  double x;
  double y;
  String? titleOverride;
  String? comment;
  final Map<String, Object?> inputOverrides;
  final Map<String, Object?> properties;

  FlowNodeInstance({
    required this.id,
    required this.typeId,
    this.x = 0.0,
    this.y = 0.0,
    this.titleOverride,
    this.comment,
    Map<String, Object?>? inputOverrides,
    Map<String, Object?>? properties,
  })  : inputOverrides = inputOverrides ?? {},
        properties = properties ?? {};

  Map<String, Object?> toJson() => {
        'id': id,
        'typeId': typeId,
        'x': x,
        'y': y,
        if (titleOverride != null) 'titleOverride': titleOverride,
        if (comment != null) 'comment': comment,
        if (inputOverrides.isNotEmpty)
          'inputOverrides': {
            for (final e in inputOverrides.entries)
              e.key: PinTypeCompatibility.encodeValue(e.value),
          },
        if (properties.isNotEmpty)
          'properties': {
            for (final e in properties.entries)
              e.key: PinTypeCompatibility.encodeValue(e.value),
          },
      };

  factory FlowNodeInstance.fromJson(Map<String, Object?> json) {
    final rawOverrides = json['inputOverrides'];
    final rawProps = json['properties'];
    return FlowNodeInstance(
      id: json['id'] as String,
      typeId: json['typeId'] as String,
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      titleOverride: json['titleOverride'] as String?,
      comment: json['comment'] as String?,
      inputOverrides: rawOverrides is Map
          ? {
              for (final e in rawOverrides.entries)
                e.key.toString(): PinTypeCompatibility.decodeValue(e.value),
            }
          : null,
      properties: rawProps is Map
          ? {
              for (final e in rawProps.entries)
                e.key.toString(): PinTypeCompatibility.decodeValue(e.value),
            }
          : null,
    );
  }
}

/// Directed wire connecting an output pin to an input pin.
final class FlowLink {
  final String id;
  final String fromNodeId;
  final String fromPinId;
  final String toNodeId;
  final String toPinId;

  const FlowLink({
    required this.id,
    required this.fromNodeId,
    required this.fromPinId,
    required this.toNodeId,
    required this.toPinId,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'fromNodeId': fromNodeId,
        'fromPinId': fromPinId,
        'toNodeId': toNodeId,
        'toPinId': toPinId,
      };

  factory FlowLink.fromJson(Map<String, Object?> json) => FlowLink(
        id: json['id'] as String,
        fromNodeId: json['fromNodeId'] as String,
        fromPinId: json['fromPinId'] as String,
        toNodeId: json['toNodeId'] as String,
        toPinId: json['toPinId'] as String,
      );
}
