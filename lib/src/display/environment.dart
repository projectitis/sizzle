import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:meta/meta.dart';

// `meta` is used for `@mustCallSuper`.

/// Base class for components that participate in environment-driven
/// lighting.
///
/// Owns a [needsRedraw] flag plus a push-based cascade that marks every
/// [EnvironmentComponent] descendant when it flips. Subclasses (notably
/// [Environment] and `LitSvgComponent`) call [markNeedsRedraw] from setters
/// that affect their rendered output, then call [clearNeedsRedraw] after
/// performing the redraw.
///
/// Any rotating component sitting between an [Environment] and an inner
/// lighting consumer must extend [EnvironmentComponent] — that is the only
/// way for its rotation to propagate the dirty state down. Wrapping
/// lighting consumers in plain [PositionComponent]s breaks the cascade.
class EnvironmentComponent extends PositionComponent {
  EnvironmentComponent({
    super.position,
    super.size,
    super.scale,
    super.angle,
    super.nativeAngle = 0,
    super.anchor,
    super.priority,
    super.children,
    super.key,
  });

  bool _needsRedraw = true;
  Environment? _env;

  /// True if this component (or an ancestor) has been marked as needing a
  /// redraw since the last [clearNeedsRedraw].
  bool get needsRedraw => _needsRedraw;

  /// The nearest [Environment] ancestor, resolved on mount. Null on an
  /// [Environment] itself unless it is nested inside another.
  Environment? get environment => _env;

  /// Mark this component and every [EnvironmentComponent] descendant as
  /// needing a redraw. Always cascades — descendants may have cleared their
  /// flag independently (e.g. after a render) since the last call. The
  /// cascade itself is short-circuited at any already-dirty descendant.
  void markNeedsRedraw() {
    _needsRedraw = true;
    _cascadeToChildren();
  }

  /// Subclasses call after performing their redraw.
  void clearNeedsRedraw() {
    _needsRedraw = false;
  }

  @override
  @mustCallSuper
  void onMount() {
    super.onMount();
    _env = findParent<Environment>();
    // Re-mounting (possibly under a new Environment) always needs a fresh
    // redraw.
    _needsRedraw = true;
  }

  @override
  @mustCallSuper
  void onRemove() {
    _env = null;
    super.onRemove();
  }

  @override
  @mustCallSuper
  void onChildrenChanged(Component child, ChildrenChangeType type) {
    super.onChildrenChanged(child, type);
    if (type == ChildrenChangeType.added && _needsRedraw) {
      _propagate(child);
    }
  }

  void _cascadeToChildren() {
    for (final c in children) {
      _propagate(c);
    }
  }

  static void _propagate(Component c) {
    if (c is EnvironmentComponent) {
      if (c._needsRedraw) return;
      c._needsRedraw = true;
      c._cascadeToChildren();
      return;
    }
    for (final gc in c.children) {
      _propagate(gc);
    }
  }
}

/// Carrier component for scene-wide lighting state.
///
/// Does not render anything itself — it is a logical container whose only
/// job is to hold a list of [Light]s. Mutating those lights through
/// [addLight] / [removeLight] / [clearLights] flips the dirty flag and
/// cascades to every [EnvironmentComponent] descendant so cached renders
/// rebuild on next frame.
class Environment extends EnvironmentComponent {
  final List<Light> lights = <Light>[];

  Environment({
    Iterable<Light>? lights,
    super.position,
    super.size,
    super.scale,
    super.angle,
    super.nativeAngle,
    super.anchor,
    super.priority,
    super.children,
    super.key,
  }) {
    if (lights != null) this.lights.addAll(lights);
  }

  void addLight(Light light) {
    lights.add(light);
    markNeedsRedraw();
  }

  void removeLight(Light light) {
    if (lights.remove(light)) markNeedsRedraw();
  }

  void clearLights() {
    if (lights.isEmpty) return;
    lights.clear();
    markNeedsRedraw();
  }

  /// Walk up [c]'s ancestors and return the nearest [Environment].
  /// Throws [StateError] if none is found.
  static Environment of(Component c) {
    final env = c.findParent<Environment>();
    if (env == null) {
      throw StateError(
        '${c.runtimeType} requires an Environment ancestor in the tree',
      );
    }
    return env;
  }
}

/// Base light. All lights have a [color] and a [strength] multiplier.
abstract class Light {
  Color color;
  double strength;
  Light({this.color = const Color(0xFFFFFFFF), this.strength = 1.0});
}

/// Non-directional fill — lifts overall scene brightness uniformly.
class AmbientLight extends Light {
  AmbientLight({super.color, super.strength});
}

/// Parallel-ray light from [direction] (think sunlight). The vector is
/// normalised at construction and on assignment, so callers may pass any
/// non-zero vector. A zero vector is preserved as-is (no NaN).
class DirectionalLight extends Light {
  DirectionalLight({
    super.color,
    super.strength,
    required Vector3 direction,
  }) : _direction = _normalised(direction);

  Vector3 _direction;
  Vector3 get direction => _direction;
  set direction(Vector3 v) => _direction = _normalised(v);

  static Vector3 _normalised(Vector3 v) {
    final out = v.clone();
    if (out.length2 > 0) out.normalize();
    return out;
  }
}
