import 'dart:math' as math;

/// Socket data/flow types supported on graph pins.
enum PinType {
  exec,
  boolVal,
  intVal,
  floatVal,
  vec2Val,
  vec3Val,
  stringVal,
  colorVal,
  any,
}

/// Direction of a socket pin on a node.
enum PinDirection {
  input,
  output,
}

/// Lightweight 2D vector value for `voxflow` graphs.
final class FlowVec2 {
  final double x;
  final double y;

  const FlowVec2([this.x = 0.0, this.y = 0.0]);

  static const zero = FlowVec2(0.0, 0.0);
  static const one = FlowVec2(1.0, 1.0);

  FlowVec2 operator +(FlowVec2 other) => FlowVec2(x + other.x, y + other.y);
  FlowVec2 operator -(FlowVec2 other) => FlowVec2(x - other.x, y - other.y);
  FlowVec2 operator *(double s) => FlowVec2(x * s, y * s);
  FlowVec2 operator -() => FlowVec2(-x, -y);

  double get length => math.sqrt(x * x + y * y);

  FlowVec2 normalized() {
    final len = length;
    return len > 1e-9 ? FlowVec2(x / len, y / len) : zero;
  }

  static FlowVec2 lerp(FlowVec2 a, FlowVec2 b, double t) =>
      FlowVec2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);

  Map<String, Object?> toJson() => {'__type': 'vec2', 'x': x, 'y': y};

  factory FlowVec2.fromJson(Map<String, Object?> json) => FlowVec2(
        (json['x'] as num?)?.toDouble() ?? 0.0,
        (json['y'] as num?)?.toDouble() ?? 0.0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlowVec2 && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'FlowVec2($x, $y)';
}

/// Lightweight 3D vector value for `voxflow` graphs.
final class FlowVec3 {
  final double x;
  final double y;
  final double z;

  const FlowVec3([this.x = 0.0, this.y = 0.0, this.z = 0.0]);

  static const zero = FlowVec3(0.0, 0.0, 0.0);
  static const one = FlowVec3(1.0, 1.0, 1.0);

  FlowVec3 operator +(FlowVec3 other) =>
      FlowVec3(x + other.x, y + other.y, z + other.z);
  FlowVec3 operator -(FlowVec3 other) =>
      FlowVec3(x - other.x, y - other.y, z - other.z);
  FlowVec3 operator *(double s) => FlowVec3(x * s, y * s, z * s);
  FlowVec3 operator -() => FlowVec3(-x, -y, -z);

  double get length => math.sqrt(x * x + y * y + z * z);

  double dot(FlowVec3 other) => x * other.x + y * other.y + z * other.z;

  FlowVec3 normalized() {
    final len = length;
    return len > 1e-9 ? FlowVec3(x / len, y / len, z / len) : zero;
  }

  static FlowVec3 lerp(FlowVec3 a, FlowVec3 b, double t) => FlowVec3(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t,
      );

  Map<String, Object?> toJson() => {'__type': 'vec3', 'x': x, 'y': y, 'z': z};

  factory FlowVec3.fromJson(Map<String, Object?> json) => FlowVec3(
        (json['x'] as num?)?.toDouble() ?? 0.0,
        (json['y'] as num?)?.toDouble() ?? 0.0,
        (json['z'] as num?)?.toDouble() ?? 0.0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlowVec3 && x == other.x && y == other.y && z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'FlowVec3($x, $y, $z)';
}

/// RGBA color value in normalized `[0..1]` space.
final class FlowColor {
  final double r;
  final double g;
  final double b;
  final double a;

  const FlowColor([this.r = 1.0, this.g = 1.0, this.b = 1.0, this.a = 1.0]);

  static const white = FlowColor(1, 1, 1, 1);
  static const black = FlowColor(0, 0, 0, 1);

  static FlowColor lerp(FlowColor c1, FlowColor c2, double t) => FlowColor(
        c1.r + (c2.r - c1.r) * t,
        c1.g + (c2.g - c1.g) * t,
        c1.b + (c2.b - c1.b) * t,
        c1.a + (c2.a - c1.a) * t,
      );

  Map<String, Object?> toJson() =>
      {'__type': 'color', 'r': r, 'g': g, 'b': b, 'a': a};

  factory FlowColor.fromJson(Map<String, Object?> json) => FlowColor(
        (json['r'] as num?)?.toDouble() ?? 1.0,
        (json['g'] as num?)?.toDouble() ?? 1.0,
        (json['b'] as num?)?.toDouble() ?? 1.0,
        (json['a'] as num?)?.toDouble() ?? 1.0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlowColor &&
          r == other.r &&
          g == other.g &&
          b == other.b &&
          a == other.a;

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => 'FlowColor($r, $g, $b, $a)';
}

/// Validates socket compatibility and performs safe implicit value coercion.
abstract final class PinTypeCompatibility {
  static bool canConnect(PinType output, PinType input) {
    if (output == PinType.exec || input == PinType.exec) {
      return output == PinType.exec && input == PinType.exec;
    }
    if (output == input || output == PinType.any || input == PinType.any) {
      return true;
    }
    // Numeric promotions/conversions
    if ((output == PinType.intVal || output == PinType.floatVal || output == PinType.boolVal) &&
        (input == PinType.intVal || input == PinType.floatVal || input == PinType.boolVal)) {
      return true;
    }
    // Vectors can promote/project or broadcast from scalar
    if ((output == PinType.vec2Val && input == PinType.vec3Val) ||
        (output == PinType.vec3Val && input == PinType.vec2Val) ||
        ((output == PinType.floatVal || output == PinType.intVal) &&
            (input == PinType.vec2Val || input == PinType.vec3Val))) {
      return true;
    }
    // Anything converts to string for logging/UI formatting
    if (input == PinType.stringVal) {
      return true;
    }
    return false;
  }

  static Object? coerce(Object? value, PinType targetType) {
    if (value == null) return defaultValueFor(targetType);
    return switch (targetType) {
      PinType.exec => null,
      PinType.any => value,
      PinType.boolVal => toBool(value),
      PinType.intVal => toInt(value),
      PinType.floatVal => toDouble(value),
      PinType.stringVal => value.toString(),
      PinType.vec2Val => toVec2(value),
      PinType.vec3Val => toVec3(value),
      PinType.colorVal => toColor(value),
    };
  }

  static Object? defaultValueFor(PinType type) => switch (type) {
        PinType.exec => null,
        PinType.boolVal => false,
        PinType.intVal => 0,
        PinType.floatVal => 0.0,
        PinType.vec2Val => FlowVec2.zero,
        PinType.vec3Val => FlowVec3.zero,
        PinType.stringVal => '',
        PinType.colorVal => FlowColor.white,
        PinType.any => null,
      };

  static bool toBool(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final lower = v.trim().toLowerCase();
      return lower == 'true' || lower == '1' || lower == 'yes';
    }
    return v != null;
  }

  static int toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is bool) return v ? 1 : 0;
    if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.round() ?? 0;
    return 0;
  }

  static double toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is bool) return v ? 1.0 : 0.0;
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static FlowVec2 toVec2(Object? v) {
    if (v is FlowVec2) return v;
    if (v is FlowVec3) return FlowVec2(v.x, v.y);
    if (v is num) return FlowVec2(v.toDouble(), v.toDouble());
    if (v is Map<String, Object?>) return FlowVec2.fromJson(v);
    return FlowVec2.zero;
  }

  static FlowVec3 toVec3(Object? v) {
    if (v is FlowVec3) return v;
    if (v is FlowVec2) return FlowVec3(v.x, v.y, 0.0);
    if (v is num) return FlowVec3(v.toDouble(), v.toDouble(), v.toDouble());
    if (v is Map<String, Object?>) return FlowVec3.fromJson(v);
    return FlowVec3.zero;
  }

  static FlowColor toColor(Object? v) {
    if (v is FlowColor) return v;
    if (v is Map<String, Object?>) return FlowColor.fromJson(v);
    return FlowColor.white;
  }

  static Object? encodeValue(Object? v) {
    if (v == null || v is bool || v is num || v is String) return v;
    if (v is FlowVec2) return v.toJson();
    if (v is FlowVec3) return v.toJson();
    if (v is FlowColor) return v.toJson();
    if (v is List) return [for (final item in v) encodeValue(item)];
    if (v is Map) {
      return {for (final e in v.entries) e.key.toString(): encodeValue(e.value)};
    }
    return v.toString();
  }

  static Object? decodeValue(Object? raw) {
    if (raw is Map) {
      final map = Map<String, Object?>.from(raw);
      return switch (map['__type']) {
        'vec2' => FlowVec2.fromJson(map),
        'vec3' => FlowVec3.fromJson(map),
        'color' => FlowColor.fromJson(map),
        _ => {
            for (final e in map.entries) e.key: decodeValue(e.value),
          },
      };
    }
    if (raw is List) {
      return [for (final item in raw) decodeValue(item)];
    }
    return raw;
  }
}
