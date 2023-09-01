import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:sizzle/src/game/services.dart';

import 'snap.dart';

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
class PlySprite {
  /// Create a new PlySprite given the source [image] and the associated
  /// [jsonData]. Use the factory method [fromPath] to load a PlySprite
  /// directly from the assets.
  PlySprite._(this._image, this._data) {
    _animName = _data.animations.keys.first;
    _anim = _data.animations.values.first;
    _size.x = _data.width;
    _size.y = _data.height;
    _reset();
  }

  /// Create a new PlySprite from an asset. A PlySprite consist of a PNG image
  /// and a JSON file with matching names (for example `mysprite.png` and
  /// `mysprite.json`).
  static Future<PlySprite> fromPath(String path) async {
    if (path.lastIndexOf('.') >= 0) {
      path = path.substring(0, path.lastIndexOf('.'));
    }
    final image = await Services.loadImage("$path.png");
    final data = await _PlySpriteData.create(path);
    return PlySprite._(image, data);
  }

  /// Called when an animation starts
  PlySpriteAnimationCallback? onAnimationStart;

  /// Called when an animation ends
  PlySpriteAnimationCallback? onAnimationEnd;

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
  PlySpriteAnimationLoopCallback? onAnimationLoop;

  /// Called after [onAnimationEnd] and when there are no more animations in the
  /// queue.
  PlySpriteAnimationCallback? onAnimationQueueEmpty;

  late final Image _image;
  late final _PlySpriteData _data;
  final Vector2 _size = Vector2.zero();
  Anchor _anchor = Anchor.topLeft;

  late _PlyAnimation _anim;
  String _animName = '';
  bool _animForward = true;
  final ListQueue<String> _queue = ListQueue<String>();

  late _PlyFrame _frame;
  int _frameIndex = 0;
  double _framePos = 0;
  double _animPos = 0;
  int _repeat = 0;

  bool _playing = false;
  get isPlaying => _playing;

  static int directionForward = 0;
  static int directionReverse = 1;
  static int directionPingpong = 2;
  static int directionPongping = 3;

  /// Reset current animation back to the start
  void _reset() {
    _animForward = _anim.direction != directionReverse;
    if (_animForward) {
      _frameIndex = 0;
    } else {
      _frameIndex = _anim.frames.length - 1;
    }
    _frame = _anim.frames[_frameIndex];
    _framePos = 0;
    _animPos = 0;
    _anchor = Anchor(_anim.anchor.x / _size.x, _anim.anchor.y / _size.y);
  }

  /// Play the [animation]. If no [animation] is specified it will start or
  /// continue playing the current animation queue and will ignore [queue].
  /// If no animation has been played previously, by default it will play the
  /// first animation in the file.
  ///
  /// Calling play with an [animation], and [queue] set to `false`, will stop
  /// all current animations and clear the queue. If [queue] is set to `true`,
  /// the [animation] will be added to the end of the queue and will play in
  /// sequence.
  void play(String? animation, {bool queue = false}) {
    if (animation == null) {
      if (!_playing) {
        if (_animPos == 0) {
          onAnimationStart?.call(this, _animName);
        }
        _playing = true;
      }
    } else {
      if (!queue) {
        _queue.clear();
        if (_playing) _stop();
      }
      _queue.add(animation);
      if (!_playing) _playNext();
    }
  }

  /// Play all [animations]. This will stop all current animations and clear
  /// the queue. If [queue] is set to `true`, the [animations] will be added
  /// to the end of the queue and will play in sequence.
  void playAll(List<String> animations, {bool queue = false}) {
    if (!queue) {
      _queue.clear();
    }
    _queue.addAll(animations);
    if (!_playing) _playNext();
  }

  bool _playNext() {
    if (_queue.isNotEmpty) {
      _animName = _queue.removeFirst();
      final anim = _data.animations[_animName];

      if (anim != null) {
        _anim = anim;
        _repeat = 0;
        _reset();
        _playing = true;
        onAnimationStart?.call(this, _animName);
        return true;
      }
    } else {
      onAnimationQueueEmpty?.call(this, '');
    }
    return false;
  }

  void _stop() {
    onAnimationEnd?.call(this, _animName);
    _playing = false;
  }

  void _loop() {
    onAnimationLoop?.call(this, _animName, _repeat);
  }

  /// Stop playing an animation. To continue again, call [play] with
  /// no arguments.
  void stop() {
    _playing = false;
  }

  /// Will clear the animation queue. Any current animation will continue to play.
  void clear() {
    _queue.clear();
  }

  /// Set the position to [pos]. If [advance] is true, will advance
  /// from the current position.
  ///
  /// Lifecycle events will be triggered, and animations will advanced through the queue. For
  /// example, consider the following queue:
  /// "Walk" - 1 second, loop twice
  /// "Yawn" - 1 second
  /// "Run" = 5 seconds
  ///
  /// If you call `scrub(4.0)` (i.e. move 4 seconds into the animation) the following will happen:
  /// "walk" will start, loop and end
  /// "Yawn" will start and end
  /// "Run" will start
  /// Although the animation will be skipped, the callbacks will still be triggered.
  void scrub(double pos, [bool advance = false]) {
    int newIndex = _frameIndex;

    void calcNewIndex() {
      _framePos = 0;
      if (_anim.direction == directionReverse) {
        newIndex = _anim.frames.length - 1;
        _animForward = false;
      } else {
        newIndex = 0;
        _animForward = true;
      }
      if (newIndex != _frameIndex) {
        _frameIndex = newIndex;
        _frame = _anim.frames[_frameIndex];
      }
    }

    if (!advance) {
      calcNewIndex();
    }
    double r;
    while (pos > 0) {
      r = (_frame.duration - _framePos) - pos;
      if (r < 0) {
        _framePos = 0;
        pos += r;
        if (_animForward) {
          newIndex++;
          if (newIndex >= _anim.frames.length) {
            // Looping
            if (_anim.repeats > 0) {
              _repeat++;
              if (_repeat >= _anim.repeats) {
                if (!_playNext()) {
                  _stop();
                  return;
                } else {
                  _loop();
                  calcNewIndex();
                  continue;
                }
              }
            }
            if (_anim.direction == directionPingpong || _anim.direction == directionPongping) {
              newIndex = _anim.frames.length - 2;
              if (newIndex < 0) newIndex = 0;
              _animForward = false;
            } else {
              newIndex = 0;
            }
          }
        } else {
          newIndex--;
          if (newIndex < 0) {
            // Looping
            if (_anim.repeats > 0) {
              _repeat++;
              if (_repeat >= _anim.repeats) {
                if (!_playNext()) {
                  _stop();
                  return;
                } else {
                  _loop();
                  calcNewIndex();
                  continue;
                }
              }
            }
            if (_anim.direction == directionPingpong || _anim.direction == directionPongping) {
              newIndex = 1;
              if (_anim.frames.length < 2) newIndex = 0;
              _animForward = true;
            } else {
              newIndex = _anim.frames.length - 1;
            }
          }
        }
        _frame = _anim.frames[newIndex];
      } else {
        _framePos += pos;
        pos = -1.0;
      }
    }
    if (newIndex != _frameIndex) {
      _frameIndex = newIndex;
      _frame = _anim.frames[_frameIndex];
    }
  }

  void update(double dt) {
    if (_playing) {
      _animPos += dt;
      scrub(dt, true);
    }
  }

  void render(Canvas canvas) {
    if (_anim.renderPartsIndividually) {
      for (var i = 0; i < _frame.transforms.length; i++) {
        canvas.drawAtlas(_image, [_frame.transforms[i]], [_frame.rects[i]], null, null, null, _frame.paints[i]);
      }
    } else {
      canvas.drawAtlas(_image, _frame.transforms, _frame.rects, null, null, null, _frame.paints[0]);
    }
  }
}

class _PlyFrame {
  _PlyFrame(this.duration);
  final double duration;
  final List<RSTransform> transforms = [];
  final List<Rect> rects = [];
  final List<Paint> paints = [];

  void addPly(Rect part, int orientation, double x, double y, int alpha, int blendmode) {
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
    transforms.add(RSTransform.fromComponents(
      rotation: rot,
      scale: 1.0,
      anchorX: 0.0,
      anchorY: 0.0,
      translateX: x + ox,
      translateY: y + oy,
    ));
    rects.add(part);
    paints.add(createPaint(alpha, blendmode));
  }

  Paint createPaint(int alpha, int blendmode) {
    final p = Paint()..color = Color.fromARGB(alpha, 0, 0, 0);
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
  _PlyAnimation(this.direction, this.repeats, double x, double y) : anchor = Vector2(x, y);
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
      final data = _PlySpriteData(await Services.loadJson("$path.json"));
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
        parts.add(Rect.fromLTWH(
          part['x'].toDouble(),
          part['y'].toDouble(),
          part['width'].toDouble(),
          part['height'].toDouble(),
        ));
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
              if (alpha != (partData['alpha'] as int) || blendmode != (partData['blendmode'] as int)) {
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
        parts.add(Rect.fromLTWH(
          part[0].toDouble(),
          part[1].toDouble(),
          part[2].toDouble(),
          part[3].toDouble(),
        ));
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
                print('Render parts individually for "${a[0]}"');
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

typedef PlySpriteAnimationCallback = void Function(PlySprite sprite, String animation);
typedef PlySpriteAnimationLoopCallback = void Function(PlySprite sprite, String animation, int loop);

/// TODO: Consider removing PlySpriteComponent and renaming PlySprite to
/// PlySpriteComponent in the future? Is there ever a use-case where the
/// non-component version is required?
class PlySpriteComponent extends PositionComponent {
  PlySpriteComponent(this.sprite) {
    anchor = sprite._anchor;
    size = sprite._size;
  }

  /// Create a new PlySpriteComponent from an asset. A PlySprite consist of a
  /// PNG image and a JSON file with matching names (for example `mysprite.png`
  /// and `mysprite.json`).
  static Future<PlySpriteComponent> fromPath(String path) async {
    return PlySpriteComponent(await PlySprite.fromPath(path));
  }

  final PlySprite sprite;

  /// Play the [animation]. If no [animation] is specified it will start or
  /// continue playing the current animation queue and will ignore [queue].
  /// If no animation has been played previously, by default this is the first
  /// animation in the file.
  ///
  /// Calling play with an [animation], and [queue] set to `false`, will stop
  /// all current animations and clear the queue. If [queue] is set to `true`,
  /// the [animation] will be added to the end of the queue and will play in
  /// sequence.
  void play(String? animation, {bool queue = false}) {
    sprite.play(animation, queue: queue);
    // Each animation can have a different anchor
    // TODO: When queue is implemented, this needs to be done onAnimationStart
    anchor = sprite._anchor;
  }

  /// Play all [animations]. This will stop all current animations and clear
  /// the queue. If [queue] is set to `true`, the [animations] will be added
  /// to the end of the queue and will play in sequence.
  void playAll(List<String> animations, {bool queue = false}) {
    sprite.playAll(animations, queue: queue);
  }

  /// Stop playing an animation. To continue again
  void stop() {
    sprite.stop();
  }

  /// Set the position to [pos]. If [advance] is true, will advance
  /// from the current position.
  void scrub(double pos, [bool advance = false]) {
    sprite.scrub(pos, advance);
  }

  @override
  void update(double dt) {
    sprite.update(dt);
    super.update(dt);
  }

  @override
  void render(Canvas canvas) {
    sprite.render(canvas);
    super.render(canvas);
  }
}

class SnapPlySpriteComponent extends PlySpriteComponent with Snap {
  SnapPlySpriteComponent(PlySprite sprite) : super(sprite);

  /// Create a new SnapPlySpriteComponent from an asset. A PlySprite consist of a
  /// PNG image and a JSON file with matching names (for example `mysprite.png`
  /// and `mysprite.json`).
  static Future<SnapPlySpriteComponent> fromPath(String path) async {
    return SnapPlySpriteComponent(await PlySprite.fromPath(path));
  }
}
