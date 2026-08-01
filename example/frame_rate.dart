import 'package:flutter/painting.dart';
import 'package:sizzle/sizzle.dart';

/// Demonstrates the two clocks: a box moved by [FrameRateScene.fixedUpdate] at
/// a fixed 60Hz, and an on-screen readout of what the render and simulation
/// clocks are actually achieving.
///
/// Tap to cycle through the frame rate modes. In the half-rate modes the
/// render readout should roughly halve while the simulation readout stays at
/// 60 - and the box should keep moving at exactly the same speed.
void main() {
  final game = SizzleGame(
    scenes: {'example': FrameRateScene.new},
    targetSize: Vector2(320, 240),
    fixedUpdateFps: 60,
    measureFps: true,
  );

  runApp(GameWidget(game: game));
}

class FrameRateScene extends Scene {
  static const _modes = FrameRateMode.values;

  final _box = RectangleComponent(
    size: Vector2(16, 16),
    paint: Paint()..color = const Color(0xff4fc3f7),
  );

  final _readout = TextComponent(
    position: Vector2(8, 8),
    textRenderer: TextPaint(
      style: const TextStyle(color: Color(0xffffffff), fontSize: 10),
    ),
  );

  int _modeIndex = 0;
  double _direction = 60.0;

  @override
  Future<void> onLoad() async {
    _box.position = Vector2(0, 112);
    add(_box);
    add(_readout);
    add(
      TapArea(
        size: game.targetGameSize,
        onTap: _cycleMode,
      ),
    );
  }

  /// Simulation. Runs at `fixedUpdateFps` regardless of the paint rate, so
  /// the box crosses the screen in the same time in every mode.
  @override
  void fixedUpdate(double fixedDt) {
    _box.position.x += _direction * fixedDt;
    if (_box.position.x < 0 || _box.position.x > game.targetGameSize.x - 16) {
      _direction = -_direction;
    }
  }

  /// Presentation. Runs once per painted frame.
  @override
  void update(double dt) {
    super.update(dt);
    _readout.text = '${game.effectiveFrameRateMode.name}\n'
        'render ${game.measuredRenderFps.toStringAsFixed(1)}fps\n'
        'fixed  ${game.measuredFixedUpdateFps.toStringAsFixed(1)}fps\n'
        'tap to change mode';
  }

  Future<void> _cycleMode() async {
    _modeIndex = (_modeIndex + 1) % _modes.length;
    final requested = _modes[_modeIndex];
    final effective = await game.setFrameRateMode(requested);
    if (effective != requested) {
      Services.log.info('$requested was not available; using $effective');
    }
  }
}

/// Invisible full-area component that turns a tap anywhere into a callback.
class TapArea extends PositionComponent with TapCallbacks {
  TapArea({required this.onTap, required Vector2 size}) : super(size: size);

  final void Function() onTap;

  @override
  void onTapDown(TapDownEvent event) => onTap();
}
