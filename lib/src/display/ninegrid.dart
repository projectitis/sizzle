import 'dart:async';
import 'dart:ui';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';

import 'snap.dart';

/// A nine-tile grid implementation
///
/// This is an alternative to [NineTileBoxComponent] that has finer control

enum NineGridRepeatType {
  /// the default. Will stretch the portion of the grid to fill the space
  stretch,

  /// Will repeat the portion of the grid to fill the space
  repeat,

  /// Will repeat the portion of the grid, alternating flipping it and then flipping it back
  mirror
}

/// Describe how each section of the [NineGrid] should repeat
class NineGridRepeat {
  NineGridRepeat({
    this.left = NineGridRepeatType.stretch,
    this.top = NineGridRepeatType.stretch,
    this.right = NineGridRepeatType.stretch,
    this.bottom = NineGridRepeatType.stretch,
    this.centerH = NineGridRepeatType.stretch,
    this.centerV = NineGridRepeatType.stretch,
  });

  NineGridRepeatType left;
  NineGridRepeatType top;
  NineGridRepeatType right;
  NineGridRepeatType bottom;
  NineGridRepeatType centerH;
  NineGridRepeatType centerV;

  static NineGridRepeat all(NineGridRepeatType type) {
    return NineGridRepeat(
      left: type,
      top: type,
      right: type,
      bottom: type,
      centerH: type,
      centerV: type,
    );
  }

  static NineGridRepeat stretch() {
    return NineGridRepeat();
  }

  static NineGridRepeat repeat() {
    return NineGridRepeat.all(NineGridRepeatType.repeat);
  }

  static NineGridRepeat mirror() {
    return NineGridRepeat.all(NineGridRepeatType.mirror);
  }

  static NineGridRepeat repeatEdges() {
    return NineGridRepeat(
      left: NineGridRepeatType.repeat,
      top: NineGridRepeatType.repeat,
      right: NineGridRepeatType.repeat,
      bottom: NineGridRepeatType.repeat,
    );
  }

  bool isAll(NineGridRepeatType type) {
    return (left == type && top == type && right == type && bottom == type && centerH == type && centerV == type);
  }
}

/// Describes the size of each section of the [NineGrid]
class NineGridSize {
  NineGridSize({
    this.left = 0.0,
    this.top = 0.0,
    this.right = 0.0,
    this.bottom = 0.0,
  });
  double left;
  double top;
  double right;
  double bottom;

  static NineGridSize all(double size) {
    return NineGridSize(
      left: size,
      top: size,
      right: size,
      bottom: size,
    );
  }
}

class NineGridComponent extends PositionComponent {
  NineGridComponent(
    Image image,
    Vector2 size, {
    NineGridSize? grid,
    NineGridRepeat? repeat,
    bool useSafeSize = false,
  }) : _image = image {
    this.grid = grid ?? NineGridSize.all(0.0);
    this.repeat = repeat ?? NineGridRepeat.all(NineGridRepeatType.stretch);
    _safeSize = useSafeSize;
    this.size = size;
  }

  Image _image;
  late NineGridSize _grid;
  late NineGridRepeat repeat;
  bool _safeSize = false;
  bool _needsComposing = true;
  bool _isComposing = false;
  Image? _output;
  BlendMode blendMode = BlendMode.srcOver;
  bool isAntiAlias = true;
  Rect _sizeRect = Rect.zero;
  Stopwatch stopWatch = Stopwatch();

  /// Set safe size
  set safeSize(bool value) {
    if (_safeSize != value) {
      _safeSize = value;
      _needsComposing = true;
    }
  }

  /// Call this to redraw the underlying image if it has changed
  void changed() {
    _needsComposing = true;
  }

  /// Set the size of the nine-grid
  set grid(NineGridSize g) {
    assert(
      g.top + g.bottom < _image.height,
      'Grid cannot be larger than image (top:${g.top} + bottom:${g.bottom} > ${_image.height})',
    );
    assert(
      g.left + g.right < _image.width,
      'Grid cannot be larger than image (left:${g.left} + right:${g.right} > ${_image.width})',
    );
    _grid = g;
    _needsComposing = true;
  }

  /// Return the size of the nine-grid
  NineGridSize get grid => _grid;

  /// Set the image used by the nine-grid
  set image(Image im) {
    assert(
      _grid.top + _grid.bottom < im.height,
      'Grid cannot be larger than image (top:${_grid.top} + bottom:${_grid.bottom} >= ${im.height})',
    );
    assert(
      _grid.left + _grid.right < im.width,
      'Grid cannot be larger than image (left:${_grid.left} + right:${_grid.right} >= ${im.width})',
    );
    _image = im;
    _needsComposing = true;
  }

  /// Get the image used by the nine-grid
  Image get image => _image;

  @override
  set size(Vector2 s) {
    if (_safeSize) {
      double mw = _grid.left + _grid.right;
      double mh = _grid.top + _grid.bottom;
      double cw = _image.width - mw;
      double ch = _image.height - mh;
      s.setValues(
        (max(0, s.x - mw) / cw).ceil() * cw + mw,
        (max(0, s.y - mh) / ch).ceil() * ch + mh,
      );
    }
    if (size.x != s.x || size.y != s.y) {
      size.setFrom(s);
      _needsComposing = true;
      _sizeRect = Rect.fromLTWH(0, 0, size.x, size.y);
    }
  }

  /// Will set the size of the image at the specified size or larger,
  /// ensuring that the repeated areas repeat cleanly in whole numbers.
  set sizeSafe(Vector2 s) {
    bool temp = _safeSize;
    _safeSize = true;
    size = s;
    _safeSize = temp;
  }

  /// Replace the image grid in one call
  void replace({
    Image? image,
    NineGridSize? grid,
    NineGridRepeat? repeat,
    bool useSafeSize = false,
  }) {
    if (image != null) _image = image;
    if (grid != null) this.grid = grid;
    if (repeat != null) this.repeat = repeat;
    _safeSize = useSafeSize;
  }

  /// Compose the final image. Will be called by first render call
  /// but can be called early to prepare the final image ahead of rendering.
  FutureOr<void> compose() async {
    if (!_needsComposing) return null;
    _needsComposing = false;
    _isComposing = true;

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = isAntiAlias;

    final Rect srcCenter = Rect.fromLTWH(
      _grid.left,
      _grid.top,
      _image.width - _grid.left - _grid.right,
      _image.height - _grid.top - _grid.bottom,
    );

    if (repeat.isAll(NineGridRepeatType.stretch)) {
      // drawImageNine is 2.5x faster
      canvas.drawImageNine(_image, srcCenter, _sizeRect, paint);
    } else {
      stopWatch.start();
      // Draw manually
      final Rect dstCenter = Rect.fromLTWH(
        _grid.left,
        _grid.top,
        max(0, size.x - _grid.left - _grid.right),
        max(0, size.y - _grid.top - _grid.bottom),
      );

      // First draw all corners as an atlas (faster than drawing one by one)
      canvas.drawAtlas(
          _image,
          <RSTransform>[
            RSTransform(1.0, 0.0, 0.0, 0.0),
            RSTransform(1.0, 0.0, dstCenter.right, 0.0),
            RSTransform(1.0, 0.0, 0.0, dstCenter.bottom),
            RSTransform(1.0, 0.0, dstCenter.right, dstCenter.bottom),
          ],
          <Rect>[
            Rect.fromLTWH(0.0, 0.0, _grid.left, _grid.top),
            Rect.fromLTWH(srcCenter.right, 0.0, _grid.right, _grid.top),
            Rect.fromLTWH(0.0, srcCenter.bottom, _grid.left, _grid.bottom),
            Rect.fromLTWH(srcCenter.right, srcCenter.bottom, _grid.right, _grid.bottom),
          ],
          null,
          null,
          null,
          paint);

      // Top
      _composeRepeat(
        canvas,
        Rect.fromLTWH(srcCenter.left, 0, srcCenter.width, srcCenter.top),
        Rect.fromLTWH(dstCenter.left, 0, dstCenter.width, dstCenter.top),
        paint,
        repeat.top == NineGridRepeatType.stretch,
      );

      // Left
      _composeRepeat(
        canvas,
        Rect.fromLTWH(0, srcCenter.top, srcCenter.left, srcCenter.height),
        Rect.fromLTWH(0, dstCenter.top, dstCenter.left, dstCenter.height),
        paint,
        false,
        repeat.left == NineGridRepeatType.stretch,
      );

      // Center
      _composeRepeat(
        canvas,
        srcCenter,
        dstCenter,
        paint,
        repeat.centerH == NineGridRepeatType.stretch,
        repeat.centerV == NineGridRepeatType.stretch,
      );

      // Right
      _composeRepeat(
        canvas,
        Rect.fromLTWH(srcCenter.right, srcCenter.top, _grid.right, srcCenter.height),
        Rect.fromLTWH(dstCenter.right, dstCenter.top, _grid.right, dstCenter.height),
        paint,
        false,
        repeat.right == NineGridRepeatType.stretch,
      );

      // Bottom
      _composeRepeat(
        canvas,
        Rect.fromLTWH(srcCenter.left, srcCenter.bottom, srcCenter.width, _grid.bottom),
        Rect.fromLTWH(dstCenter.left, dstCenter.bottom, dstCenter.width, _grid.bottom),
        paint,
        repeat.bottom == NineGridRepeatType.stretch,
      );

      stopWatch.stop();
      print('canvas operations took ${stopWatch.elapsedMicroseconds}');
    }

    // Create image
    final picture = recorder.endRecording();
    picture.toImage(size.x.ceil(), size.y.ceil()).then((value) {
      _output = value;
      _isComposing = false;
    });
  }

  void _composeRepeat(Canvas canvas, Rect src, Rect dst, Paint paint, [bool stretchX = false, bool stretchY = false]) {
    if (src.isEmpty || dst.isEmpty) return;

    Rect start = Rect.fromLTWH(
      dst.left,
      dst.top,
      stretchX ? dst.width : src.width,
      stretchY ? dst.height : src.height,
    );
    Rect patch = Rect.fromLTRB(
      start.left,
      start.top,
      min(start.left + start.width, dst.right),
      min(start.top + start.height, dst.bottom),
    );

    do {
      do {
        canvas.drawImageRect(_image, src, patch, paint);
        patch = Rect.fromLTRB(
          patch.left + start.width,
          patch.top,
          min(patch.right + start.width, dst.right),
          patch.bottom,
        );
      } while (patch.left < dst.right);
      patch = Rect.fromLTRB(
        start.left,
        patch.bottom,
        min(start.left + start.width, dst.right),
        min(patch.bottom + start.height, dst.bottom),
      );
    } while (patch.top < dst.bottom);
  }

  @mustCallSuper
  @override
  void render(Canvas canvas) {
    if (_needsComposing && !_isComposing) {
      compose();
      return;
    } else if (_isComposing || _output == null || _output?.width == 0 || _output?.height == 0) {
      return;
    }

    canvas.drawImageRect(
      _output!,
      _sizeRect,
      _sizeRect,
      Paint()
        ..blendMode = blendMode
        ..isAntiAlias = isAntiAlias,
    );
  }
}

class BitmapNineGridComponent extends NineGridComponent with Snap {
  BitmapNineGridComponent(
    Image image,
    Vector2 size, {
    NineGridSize? grid,
    NineGridRepeat? repeat,
    bool useSafeSize = false,
  }) : super(
          image,
          size,
          grid: grid,
          repeat: repeat,
          useSafeSize: useSafeSize,
        );
}
