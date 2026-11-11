import 'blackboard.dart';
import 'node.dart';
import 'registry.dart';
import 'types.dart';

/// Topological validation & connection error metadata.
final class GraphValidationResult {
  final bool isValid;
  final bool hasDataCycle;
  final List<String> errors;
  final List<String> topologicalOrder;

  const GraphValidationResult({
    required this.isValid,
    required this.hasDataCycle,
    required this.errors,
    required this.topologicalOrder,
  });
}

/// Complete visual node graph definition containing node instances, links, blackboard
/// defaults, subgraphs, and structural validation/sorting algorithms.
final class FlowGraph {
  final String name;
  final FlowNodeRegistry registry;
  final FlowBlackboard blackboard;
  final Map<String, FlowNodeInstance> _nodes = {};
  final List<FlowLink> _links = [];
  final Map<String, FlowGraph> subgraphs = {};

  int _nextNodeSeq = 1;
  int _nextLinkSeq = 1;

  FlowGraph({
    this.name = 'FlowGraph',
    FlowNodeRegistry? registry,
    FlowBlackboard? blackboard,
  })  : registry = registry ?? FlowNodeRegistry(),
        blackboard = blackboard ?? FlowBlackboard();

  Map<String, FlowNodeInstance> get nodes => Map.unmodifiable(_nodes);
  List<FlowLink> get links => List.unmodifiable(_links);

  /// Places a new node of registered [typeId] onto the graph at canvas coords ([x], [y]).
  FlowNodeInstance addNode(
    String typeId, {
    String? id,
    double x = 0.0,
    double y = 0.0,
    String? titleOverride,
    String? comment,
    Map<String, Object?>? inputs,
    Map<String, Object?>? properties,
  }) {
    if (!registry.contains(typeId)) {
      throw ArgumentError.value(typeId, 'typeId', 'Unknown node typeId');
    }
    var nodeId = id;
    if (nodeId == null) {
      do {
        nodeId = 'n${_nextNodeSeq++}';
      } while (_nodes.containsKey(nodeId));
    } else if (_nodes.containsKey(nodeId)) {
      throw ArgumentError.value(nodeId, 'id', 'Duplicate node id in FlowGraph');
    }

    final instance = FlowNodeInstance(
      id: nodeId,
      typeId: typeId,
      x: x,
      y: y,
      titleOverride: titleOverride,
      comment: comment,
      inputOverrides: inputs,
      properties: properties,
    );
    _nodes[nodeId] = instance;
    return instance;
  }

  bool removeNode(String nodeId) {
    final removed = _nodes.remove(nodeId);
    if (removed == null) return false;
    _links.removeWhere((l) => l.fromNodeId == nodeId || l.toNodeId == nodeId);
    return true;
  }

  FlowNodeInstance? getNode(String nodeId) => _nodes[nodeId];

  FlowNodeDef? getNodeDef(String nodeId) {
    final inst = _nodes[nodeId];
    return inst == null ? null : registry.get(inst.typeId);
  }

  /// Connects [fromNodeId].[fromPinId] (output) to [toNodeId].[toPinId] (input).
  ///
  /// Enforces socket existence, directionality, and [PinTypeCompatibility]. If the
  /// target input pin accepts only one link, any prior incoming wire on that pin
  /// is automatically replaced.
  FlowLink connect(
    String fromNodeId,
    String fromPinId,
    String toNodeId,
    String toPinId, {
    String? id,
  }) {
    final fromNode = _nodes[fromNodeId];
    final toNode = _nodes[toNodeId];
    if (fromNode == null) throw ArgumentError('Missing source node "$fromNodeId"');
    if (toNode == null) throw ArgumentError('Missing target node "$toNodeId"');
    if (fromNodeId == toNodeId) {
      throw ArgumentError('Cannot connect a node "$fromNodeId" to itself');
    }

    final fromDef = registry.get(fromNode.typeId);
    final toDef = registry.get(toNode.typeId);
    if (fromDef == null) throw StateError('Unregistered node type "${fromNode.typeId}"');
    if (toDef == null) throw StateError('Unregistered node type "${toNode.typeId}"');

    final fromPin = fromDef.findPin(fromPinId, PinDirection.output);
    final toPin = toDef.findPin(toPinId, PinDirection.input);
    if (fromPin == null) {
      throw ArgumentError('Output pin "$fromPinId" not found on "${fromDef.typeId}"');
    }
    if (toPin == null) {
      throw ArgumentError('Input pin "$toPinId" not found on "${toDef.typeId}"');
    }
    if (!PinTypeCompatibility.canConnect(fromPin.type, toPin.type)) {
      throw ArgumentError(
        'Incompatible pin types: ${fromPin.type.name} -> ${toPin.type.name}',
      );
    }

    // Remove exact duplicate if already present.
    _links.removeWhere(
      (l) =>
          l.fromNodeId == fromNodeId &&
          l.fromPinId == fromPinId &&
          l.toNodeId == toNodeId &&
          l.toPinId == toPinId,
    );

    if (!toPin.allowMultipleConnections) {
      _links.removeWhere((l) => l.toNodeId == toNodeId && l.toPinId == toPinId);
    }
    if (fromPin.type == PinType.exec && !fromPin.allowMultipleConnections) {
      // One exec output pin drives a single downstream chain at a time cleanly.
      _links.removeWhere((l) => l.fromNodeId == fromNodeId && l.fromPinId == fromPinId);
    }

    final linkId = id ?? 'l${_nextLinkSeq++}';
    final link = FlowLink(
      id: linkId,
      fromNodeId: fromNodeId,
      fromPinId: fromPinId,
      toNodeId: toNodeId,
      toPinId: toPinId,
    );
    _links.add(link);
    return link;
  }

  /// Non-throwing variant of [connect]. Returns `null` if invalid.
  FlowLink? tryConnect(
    String fromNodeId,
    String fromPinId,
    String toNodeId,
    String toPinId,
  ) {
    try {
      return connect(fromNodeId, fromPinId, toNodeId, toPinId);
    } catch (_) {
      return null;
    }
  }

  bool disconnect(String linkId) {
    final before = _links.length;
    _links.removeWhere((l) => l.id == linkId);
    return _links.length != before;
  }

  int disconnectPin(String nodeId, String pinId) {
    final before = _links.length;
    _links.removeWhere(
      (l) =>
          (l.fromNodeId == nodeId && l.fromPinId == pinId) ||
          (l.toNodeId == nodeId && l.toPinId == pinId),
    );
    return before - _links.length;
  }

  FlowLink? findIncomingDataLink(String nodeId, String inputPinId) {
    for (final l in _links) {
      if (l.toNodeId == nodeId && l.toPinId == inputPinId) return l;
    }
    return null;
  }

  List<FlowLink> findOutgoingExecLinks(String nodeId, String outputExecPinId) => [
        for (final l in _links)
          if (l.fromNodeId == nodeId && l.fromPinId == outputExecPinId) l,
      ];

  /// Computes Kahn topological ordering of nodes across data (or all) edges.
  /// Returns `null` when a cycle exists.
  List<String>? topologicalOrder({bool dataLinksOnly = true}) {
    final inDegree = {for (final id in _nodes.keys) id: 0};
    final adj = {for (final id in _nodes.keys) id: <String>[]};

    for (final link in _links) {
      if (!_nodes.containsKey(link.fromNodeId) ||
          !_nodes.containsKey(link.toNodeId)) {
        continue;
      }
      if (dataLinksOnly) {
        final fromDef = getNodeDef(link.fromNodeId);
        final pin = fromDef?.findPin(link.fromPinId, PinDirection.output);
        if (pin?.type == PinType.exec) continue;
      }
      adj[link.fromNodeId]!.add(link.toNodeId);
      inDegree[link.toNodeId] = inDegree[link.toNodeId]! + 1;
    }

    final queue = <String>[
      for (final e in inDegree.entries)
        if (e.value == 0) e.key,
    ];
    final sorted = <String>[];
    var head = 0;

    while (head < queue.length) {
      final curr = queue[head++];
      sorted.add(curr);
      for (final next in adj[curr]!) {
        final d = inDegree[next]! - 1;
        inDegree[next] = d;
        if (d == 0) queue.add(next);
      }
    }

    return sorted.length == _nodes.length ? sorted : null;
  }

  bool hasCycles({bool dataLinksOnly = true}) =>
      topologicalOrder(dataLinksOnly: dataLinksOnly) == null;

  GraphValidationResult validate() {
    final errors = <String>[];
    for (final node in _nodes.values) {
      if (!registry.contains(node.typeId)) {
        errors.add('Unknown node type "${node.typeId}" on node "${node.id}"');
      }
    }
    for (final link in _links) {
      if (!_nodes.containsKey(link.fromNodeId) || !_nodes.containsKey(link.toNodeId)) {
        errors.add('Link "${link.id}" references missing node');
      }
    }
    final order = topologicalOrder(dataLinksOnly: true);
    final cycle = order == null;
    if (cycle) {
      errors.add('Cyclic dataflow dependency detected in graph "$name"');
    }
    return GraphValidationResult(
      isValid: errors.isEmpty,
      hasDataCycle: cycle,
      errors: errors,
      topologicalOrder: order ?? const [],
    );
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'nodes': [for (final n in _nodes.values) n.toJson()],
        'links': [for (final l in _links) l.toJson()],
        'blackboard': blackboard.toJson(),
        if (subgraphs.isNotEmpty)
          'subgraphs': {
            for (final e in subgraphs.entries) e.key: e.value.toJson(),
          },
      };

  factory FlowGraph.fromJson(
    Map<String, Object?> json, {
    FlowNodeRegistry? registry,
  }) {
    final reg = registry ?? FlowNodeRegistry();
    final rawBb = json['blackboard'];
    final graph = FlowGraph(
      name: (json['name'] as String?) ?? 'FlowGraph',
      registry: reg,
      blackboard: rawBb is Map
          ? FlowBlackboard.fromJson(Map<String, Object?>.from(rawBb))
          : FlowBlackboard(),
    );

    final rawNodes = json['nodes'];
    if (rawNodes is List) {
      for (final item in rawNodes) {
        if (item is Map) {
          final node = FlowNodeInstance.fromJson(Map<String, Object?>.from(item));
          graph._nodes[node.id] = node;
        }
      }
    }

    final rawLinks = json['links'];
    if (rawLinks is List) {
      for (final item in rawLinks) {
        if (item is Map) {
          graph._links.add(FlowLink.fromJson(Map<String, Object?>.from(item)));
        }
      }
    }

    final rawSubs = json['subgraphs'];
    if (rawSubs is Map) {
      for (final e in rawSubs.entries) {
        if (e.value is Map) {
          graph.subgraphs[e.key.toString()] = FlowGraph.fromJson(
            Map<String, Object?>.from(e.value as Map),
            registry: reg,
          );
        }
      }
    }

    return graph;
  }
}
