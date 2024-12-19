import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../utils/services.dart';
import './snap.dart';

/// A PlySprite is an animated sprite made up of many layers. The format is
/// very space-efficient because it re-uses a lot of parts that make up the
/// sprite, resulting in a much smaller image (sprite sheet).
///
/// A 'part' of a PlySprite can be re-used on many frames. A single part
/// can also be rotated (in 90 degree steps) and re-used without making the
/// sprite sheet (image) bigger.
///
/// The format was originally intended for systems that have much smaller
/// memory (such as microcontrollers), but is useful for any purpose that
/// benefits from a smaller memory or bundle size. It's especially handy for
/// reasonably small sprites (like you get in pixel-art games) and if you
/// have a character with a large number of animations (walk, jump, pick-up,
/// talk, etc). The resulting sprite sheet will be much, much smaller.
///
/// Sizzle includes a script that allows exporting ply-sprites from Aseprite.
/// See the comments in `/scripts/aseprite/ply-sprite.lua` for how to use it.
///
/// The format is quite straight-forward and exporters could be implemented quite
/// easily for other applications.
class PlySpriteComponent extends PositionComponent {
  /// Create a new PlySprite given the source [image] and the associated
  /// [jsonData]. Use the factory method [fromPath] to load a PlySprite
  /// directly from the assets.
  PlySpriteComponent._(this._image, this._data) {
    _queue.add(PlyAnimProps(_data.animations.keys.first));
    _next();
    _reset();
    size.x = _data.width;
    size.y = _data.height;
  }

  /// Create a new PlySpriteComponent from an asset. A PlySprite consist of a
  /// PNG image and a JSON file with matching names (for example `mysprite.png`
  /// and `mysprite.json`). Provide the path to the assets without the
  /// extension (for example `images/mysprite`).
  static Future<PlySpriteComponent> fromPath(String path) async {
    if (path.lastIndexOf('.') >= 0) {
      path = path.substring(0, path.lastIndexOf('.'));
    }
    final image = await Services.images.load(path: "$path.png");
    final data = await _PlySpriteData.create(path);
    return PlySpriteComponent._(image, data);
  }

  /// Called when an animation starts
  PlyCallback? onAnimationStart;

  /// Called when an animation ends
  PlyCallback? onAnimationEnd;

  /// Called when an animation is looping and starts a subsequent loop. A looping
  /// animation (repeat=3) will undergo a life cycle like this:
  ///   onAnimationStart  ->
  ///   onAnimationLoop   ->
  ///   onAnimationLoop   ->
  ///   onAnimationEnd    !
  /// A looping ping-pong animation (repeat=3) will look like this:
  ///   onAnimationStart  ->
  ///   onAnimationLoop   <-
  ///   onAnimationLoop   ->
  ///   onAnimationEnd    !
  PlyLoopCallback? onAnimationLoop;

  /// Called after [onAnimationEnd] and when there are no more animations in the
  /// queue.
  PlyCallback? onAnimationQueueEmpty;

  late final Image _image;
  late final _PlySpriteData _data;

  _PlyAnimation? _anim;
  PlyAnimProps? _current;
  int _animStep = 1;
  final ListQueue<PlyAnimProps> _queue = ListQueue<PlyAnimProps>();

  late _PlyFrame _frame;
  int _frameIndex = 0;
  double _framePos = 0;
  int _repeat = 0;

  double _animPos = 0;
  get animPosition => _animPos;

  bool _playing = false;
  get isPlaying => _playing;

  void _reset() {
    if (_anim == null || _current == null) {
      return;
    }
    _animStep = _current!.direction == PlyDirection.reverse ||
            _current!.direction == PlyDirection.pongping
        ? -1
        : 1;
    if (_animStep > 0) {
      _frameIndex = 0;
    } else {
      _frameIndex = _anim!.frames.length - 1;
    }
    _frame = _anim!.frames[_frameIndex];
    _framePos = 0;
    _animPos = 0;
    _repeat = 0;
    anchor = Anchor(_anim!.anchor.x / size.x, _anim!.anchor.y / size.y);
  }

  /// Play the supplied [animation] by name.
  ///
  /// Any of the animation properties can be overwritten by supplying a new animation [directions], a number of
  /// [repeats] for looping, or adjust the [speed]. A speed of `1.0` is normal. `1.2` is 20% faster, and `0.5` is
  /// half-speed.
  ///
  /// If [addToQueue] is false, any current animation will immediately stop playing (note: no callbacks will be
  /// triggered) and the queue will cleared before playing this animation.
  ///
  /// If [addToQueue] is true, the animation will be added to the end of any existing animations on the queue, and any
  /// playing animation will continue.
  ///
  /// Also see [playAll]
  void play(
    String animation, {
    int direction = -1,
    int repeats = -1,
    double speed = 1.0,
    bool addToQueue = false,
  }) {
    final anim = PlyAnimProps(
      animation,
      direction: direction,
      repeats: repeats,
      speed: speed,
    );
    if (!addToQueue) {
      _queue.clear();
      _playing = false;
    }
    _queue.add(anim);
    _play(true);
  }

  /// Play all [animations] one after the other.
  ///
  /// If [addToQueue] is false, any current animation will immediately stop playing (note: no callbacks will be
  /// triggered) and the queue will be replaced completely by [animations].
  ///
  /// If [addToQueue] is true, the [animations] will be added to any existing animations on the queue, and any
  /// playing animation will continue.
  ///
  /// Also see [play]
  void playAll(List<PlyAnimProps> animations, {bool addToQueue = false}) {
    if (!addToQueue) {
      _queue.clear();
      _playing = false;
    }
    _queue.addAll(animations);
    _play(true);
  }

  /// Pause the current animation. Use [resume] to continue after pausing.
  void pause() {
    _playing = false;
  }

  /// Resume an animation that was paused using [pause] or [stop]
  void resume() {
    _playing = true;
  }

  /// Stop playing the current animation and remove it from the queue. Since the animation didn't naturally complete,
  /// no callbacks will be triggered.
  ///
  /// If [clearQueue] is `false` then the rest of the queue will not be affected. Use [resume], [play] or [playAll] to
  /// play more animations.
  ///
  /// If [clearQueue] is `true` then the queue will be cleared. Use [play] or [playAll] to play more animations.
  void stop({bool clearQueue = false}) {
    if (clearQueue) {
      clear();
    }
    _playing = false;
  }

  /// Clear the animation queue. Any current animation will continue to play. Also see [stop].
  void clear() {
    _queue.clear();
  }

  /// Set the animation [position] in seconds. If [fromStart] is `true` the position will be set from the start of the
  /// current animation. If [fromStart] is `false` then the position will advance from the current position.
  ///
  /// Lifecycle events will be triggered, and animations will loop and advance through the queue. For
  /// example, consider the following queue:
  /// - "Walk" - 1 second, loop twice
  /// - "Yawn" - 1 second
  /// - "Run" = 5 seconds
  ///
  /// If you call `advance(4.0, fromStart: true)` (i.e. move 4 seconds into the animation) the following will happen:
  /// - "walk" will start, loop and end
  /// - "Yawn" will start and end
  /// - "Run" will start
  ///
  /// If the animation is playing when [advance] is called callbacks will be triggered. If the animation is not playing,
  /// callbacks will not be triggered.
  void advance(double position, [bool fromStart = false]) {
    if (_anim == null || _current == null) return;
    int newIndex = _frameIndex;

    if (fromStart) {
      _reset();
    }

    double r; // time remaining for frame
    while (position > 0) {
      r = _frame.duration - _framePos;
      if ((r - position) < 0) {
        // reached end of frame
        _framePos = 0;
        position -= r;
        _animPos += r;
        newIndex += _animStep;
        if (newIndex >= _anim!.frames.length || newIndex < 0) {
          // reached end of animation
          if ((_current!.repeats == 0) || ++_repeat < _current!.repeats) {
            // Looping
            _loop();
            // Reverse direction if required
            if (_current!.direction == PlyDirection.pingpong ||
                _current!.direction == PlyDirection.pongping) {
              _animStep = -_animStep;
            }
            // Calc new frame
            if (_animStep > 0) {
              newIndex = 0;
            } else {
              newIndex = _anim!.frames.length - 1;
            }
          }
          // Not looping. Go to next anim in queue
          else if (_play(false)) {
            // Calc first frame
            if (_current!.direction == PlyDirection.reverse ||
                _current!.direction == PlyDirection.pongping) {
              newIndex = _anim!.frames.length - 1;
              _animStep = -1;
            } else {
              newIndex = 0;
              _animStep = 1;
            }
          }
          // Stop
          else {
            _stop();
            return;
          }
        }
        _frame = _anim!.frames[newIndex];
      } else {
        _framePos += position;
        _animPos += position;
        position = -1.0;
      }
    }
    if (newIndex != _frameIndex) {
      _frameIndex = newIndex;
      _frame = _anim!.frames[_frameIndex];
    }
  }

  bool _play(bool allowStart) {
    if (_playing) {
      onAnimationEnd?.call(this, _current!.name);
    }
    if (_next()) {
      if (_playing || (!_playing && allowStart)) {
        _playing = true;
        onAnimationStart?.call(this, _current!.name);
      }
      return true;
    }
    return false;
  }

  bool _next() {
    if (!_queue.isEmpty) {
      _current = _queue.removeFirst();
      final anim = _data.animations[_current!.name];

      if (anim != null) {
        _anim = anim;
        _current!._applyData(_anim!);
        _reset();
        return true;
      }
    }

    return false;
  }

  void _stop() {
    if (_playing) {
      _playing = false;
      if (_queue.isEmpty) {
        onAnimationQueueEmpty?.call(this, '');
      }
    }
  }

  void _loop() {
    if (_playing) {
      onAnimationLoop?.call(this, _current!.name, _repeat);
    }
  }

  @override
  void update(double dt) {
    if (_playing) {
      advance(dt);
    }
    super.update(dt);
  }

  @override
  void render(Canvas canvas) {
    if (_anim != null) {
      if (_anim!.renderPartsIndividually) {
        for (var i = 0; i < _frame.transforms.length; i++) {
          canvas.drawAtlas(
            _image,
            [_frame.transforms[i]],
            [_frame.rects[i]],
            null,
            null,
            null,
            _frame.paints[i],
          );
        }
      } else {
        canvas.drawAtlas(
          _image,
          _frame.transforms,
          _frame.rects,
          null,
          null,
          null,
          _frame.paints[0],
        );
      }
    }
    super.render(canvas);
  }
}

typedef PlyCallback = void Function(
  PlySpriteComponent sprite,
  String animation,
);

typedef PlyLoopCallback = void Function(
  PlySpriteComponent sprite,
  String animation,
  int loop,
);

class PlyDirection {
  static const forward = 0;
  static const reverse = 1;
  static const pingpong = 2;
  static const pongping = 3;
}

/// Settings for an animation to play.
///
/// Provide at least the [name] of the animation. You can override specific
/// settings for the animation. Set [direction] to change the animation
/// direction (see [PlyDirection]), set [repeats] to change the number of times
/// the animation loops, and set [speed] to change the animation playback speed
/// by a factor.
///
/// For example, `speed = 1.0` is default, `speed = 0.9` plays it at 90% of the
/// original speed, and `speed = 0.5` will play it at half speed.
class PlyAnimProps {
  PlyAnimProps(
    this.name, {
    this.direction = -1,
    this.repeats = -1,
    double speed = 1.0,
  }) : _speed = max(0, speed);
  String name;
  int direction;
  int repeats;
  double _speed;

  /// Copy the settings from another [PlyAnimProps] object.
  void copy(PlyAnimProps anim) {
    name = anim.name;
    direction = anim.direction;
    repeats = anim.repeats;
    _speed = anim._speed;
  }

  void _applyData(_PlyAnimation anim) {
    if (direction < 0) direction = anim.direction;
    if (repeats < 0) repeats = anim.repeats;
    print(
      "PlyAnimProps $name, dir: $direction, repeats: $repeats, speed: $_speed",
    );
  }
}

class _PlyFrame {
  _PlyFrame(this.duration);
  final double duration;
  final List<RSTransform> transforms = [];
  final List<Rect> rects = [];
  final List<Paint> paints = [];

  void addPly(
    Rect part,
    int orientation,
    double x,
    double y,
    int alpha,
    int blendmode,
  ) {
    double rot = 0;
    double ox = 0;
    double oy = 0;
    if (orientation == 4) {
      rot = pi * 0.5;
      ox = part.width;
    } else if (orientation == 3) {
      rot = pi;
      oy = part.height;
      ox = part.width;
    } else if (orientation == 7) {
      rot = pi * 1.5;
      oy = part.height;
    }
    transforms.add(
      RSTransform.fromComponents(
        rotation: rot,
        scale: 1.0,
        anchorX: 0.0,
        anchorY: 0.0,
        translateX: x + ox,
        translateY: y + oy,
      ),
    );
    rects.add(part);
    paints.add(createPaint(alpha, blendmode));
  }

  Paint createPaint(int alpha, int blendmode) {
    final p = Paint()..color = Color.fromARGB(alpha, 0, 0, 0);
    // Blend mode values are from Aseprite
    switch (blendmode) {
      case 14:
        p.blendMode = BlendMode.multiply;
        break;
      case 15:
        p.blendMode = BlendMode.screen;
        break;
      case 16:
        p.blendMode = BlendMode.overlay;
        break;
      case 17:
        p.blendMode = BlendMode.darken;
        break;
      case 18:
        p.blendMode = BlendMode.lighten;
        break;
      case 19:
        p.blendMode = BlendMode.colorDodge;
        break;
      case 20:
        p.blendMode = BlendMode.colorBurn;
        break;
      case 21:
        p.blendMode = BlendMode.hardLight;
        break;
      case 22:
        p.blendMode = BlendMode.softLight;
        break;
      case 23:
        p.blendMode = BlendMode.difference;
        break;
      case 24:
        p.blendMode = BlendMode.exclusion;
        break;
      case 25:
        p.blendMode = BlendMode.hue;
        break;
      case 26:
        p.blendMode = BlendMode.saturation;
        break;
      case 27:
        p.blendMode = BlendMode.color;
        break;
      case 28:
        p.blendMode = BlendMode.luminosity;
        break;
      case 29:
        p.blendMode = BlendMode.plus; // addition ?
        break;
      case 30:
        p.blendMode = BlendMode.srcOver; // subtract ?
        break;
      case 31:
        p.blendMode = BlendMode.srcOver; // divide (opposite of subtract) ?
        break;
      default: // 3
        p.blendMode = BlendMode.srcOver; // normal
        break;
    }
    return p;
  }
}

class _PlyAnimation {
  _PlyAnimation(this.direction, this.repeats, double x, double y)
      : anchor = Vector2(x, y);
  final Vector2 anchor;
  final int direction;
  final int repeats;
  final List<_PlyFrame> frames = [];
  bool renderPartsIndividually = false;
}

class _PlySpriteData {
  static final Map<String, _PlySpriteData> _cache = {};

  static FutureOr<_PlySpriteData> create(String path) async {
    if (!_cache.containsKey(path)) {
      final data = _PlySpriteData(
        await Services.files.loadJson(path: "$path.json"),
      );
      _cache[path] = data;
    }
    return _cache[path]!;
  }

  _PlySpriteData(dynamic json) {
    bool first = true;
    int alpha = 0;
    int blendmode = 0;

    /// Verbose JSON
    if (json is Map) {
      width = json['width'].toDouble();
      height = json['height'].toDouble();

      for (final part in json['parts']) {
        parts.add(
          Rect.fromLTWH(
            part['x'].toDouble(),
            part['y'].toDouble(),
            part['width'].toDouble(),
            part['height'].toDouble(),
          ),
        );
      }

      json['animations'].forEach((name, animData) {
        final anim = _PlyAnimation(
          animData['direction'] as int,
          animData['repeats'] as int,
          animData['anchor']['x'].toDouble(),
          animData['anchor']['y'].toDouble(),
        );

        animData['frames'].forEach((frameData) {
          final frame = _PlyFrame(frameData['duration']);
          frameData['parts'].forEach((partData) {
            frame.addPly(
              parts[partData['index'] as int],
              partData['orientation'] as int,
              partData['x'].toDouble(),
              partData['y'].toDouble(),
              partData['alpha'] as int,
              partData['blendmode'] as int,
            );
            if (first) {
              alpha = partData['alpha'] as int;
              blendmode = partData['blendmode'] as int;
              first = false;
            } else {
              if (alpha != (partData['alpha'] as int) ||
                  blendmode != (partData['blendmode'] as int)) {
                anim.renderPartsIndividually = true;
              }
            }
          });
          anim.frames.add(frame);
        });
        animations[name] = anim;
      });
    }

    /// Condensed JSON
    else {
      width = json[0][0].toDouble();
      height = json[0][1].toDouble();

      for (final part in json[1]) {
        parts.add(
          Rect.fromLTWH(
            part[0].toDouble(),
            part[1].toDouble(),
            part[2].toDouble(),
            part[3].toDouble(),
          ),
        );
      }

      for (final a in json[2]) {
        final anim = _PlyAnimation(
          a[1] as int,
          a[2] as int,
          a[3][0].toDouble(),
          a[3][1].toDouble(),
        );

        for (final f in a[4]) {
          final frame = _PlyFrame(f[0] as double);

          for (final p in f[1]) {
            frame.addPly(
              parts[p[0] as int], // Part
              p[1] as int, // Orientation
              p[2].toDouble(), // x
              p[3].toDouble(), // y
              p[4] as int, // Alpha
              p[5] as int, // BlendMode
            );
            if (first) {
              alpha = p[4] as int;
              blendmode = p[5] as int;
              first = false;
            } else {
              if (alpha != (p[4] as int) || blendmode != (p[5] as int)) {
                anim.renderPartsIndividually = true;
              }
            }
          }

          anim.frames.add(frame);
        }

        animations[a[0] as String] = anim;
      }
    }
  }

  late final double width;
  late final double height;
  final List<Rect> parts = [];
  final Map<String, _PlyAnimation> animations = {};
}

class SnapPlySpriteComponent extends PlySpriteComponent with Snap {
  SnapPlySpriteComponent._(Image image, _PlySpriteData data)
      : super._(image, data);

  /// Create a new SnapPlySpriteComponent from an asset. A PlySprite consist of a
  /// PNG image and a JSON file with matching names (for example `mysprite.png`
  /// and `mysprite.json`). Provide the path to the assets without the
  /// extension (for example `images/mysprite`).
  static Future<SnapPlySpriteComponent> fromPath(String path) async {
    if (path.lastIndexOf('.') >= 0) {
      path = path.substring(0, path.lastIndexOf('.'));
    }
    final image = await Services.images.load(path: "$path.png");
    final data = await _PlySpriteData.create(path);
    return SnapPlySpriteComponent._(image, data);
  }
}
