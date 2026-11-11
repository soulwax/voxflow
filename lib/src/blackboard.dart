import 'types.dart';

typedef BlackboardListener = void Function(String key, Object? oldValue, Object? newValue);

/// Reactive typed variable store shared across nodes in a `FlowGraph` runtime.
final class FlowBlackboard {
  final Map<String, Object?> _values = {};
  final List<BlackboardListener> _listeners = [];

  FlowBlackboard([Map<String, Object?>? initial]) {
    if (initial != null) {
      _values.addAll(initial);
    }
  }

  Map<String, Object?> get entries => Map.unmodifiable(_values);
  Iterable<String> get keys => _values.keys;
  bool has(String key) => _values.containsKey(key);

  Object? get(String key, [Object? fallback]) =>
      _values.containsKey(key) ? _values[key] : fallback;

  T getAs<T>(String key, T fallback) {
    final val = _values[key];
    return val is T ? val : fallback;
  }

  void set(String key, Object? value) {
    final prev = _values[key];
    if (prev == value && _values.containsKey(key)) return;
    _values[key] = value;
    for (final listener in List<BlackboardListener>.of(_listeners)) {
      listener(key, prev, value);
    }
  }

  bool remove(String key) {
    if (!_values.containsKey(key)) return false;
    final prev = _values.remove(key);
    for (final listener in List<BlackboardListener>.of(_listeners)) {
      listener(key, prev, null);
    }
    return true;
  }

  void clear() {
    if (_values.isEmpty) return;
    final oldKeys = _values.entries.toList();
    _values.clear();
    for (final entry in oldKeys) {
      for (final listener in List<BlackboardListener>.of(_listeners)) {
        listener(entry.key, entry.value, null);
      }
    }
  }

  void addListener(BlackboardListener listener) => _listeners.add(listener);
  void removeListener(BlackboardListener listener) => _listeners.remove(listener);

  FlowBlackboard clone() => FlowBlackboard(Map<String, Object?>.of(_values));

  Map<String, Object?> toJson() => {
        for (final e in _values.entries)
          e.key: PinTypeCompatibility.encodeValue(e.value),
      };

  factory FlowBlackboard.fromJson(Map<String, Object?> json) => FlowBlackboard({
        for (final e in json.entries)
          e.key: PinTypeCompatibility.decodeValue(e.value),
      });
}
