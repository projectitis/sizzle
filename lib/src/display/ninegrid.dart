import 'dart:async';
import 'dart:ui';
import 'dart:math';

import 'package:meta/meta.dart';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:sizzle/src/display/sprite.dart';

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

  static NineGridRepeat all(NineGridRepeatType repeat) {
    return NineGridRepeat(
      left: repeat,
      top: repeat,
      right: repeat,
      bottom: repeat,
      centerH: repeat,
      centerV: repeat,
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
  }) : _image = image {
    this.grid = grid ?? NineGridSize.all(0.0);
    this.repeat = repeat ?? NineGridRepeat.all(NineGridRepeatType.stretch);
    this.size = size;
  }

  Image _image;
  late NineGridSize _grid;
  late NineGridRepeat repeat;
  bool _needsComposing = true;
  bool _isComposing = false;
  Image? _output;
  BlendMode blendMode = BlendMode.srcOver;
  bool isAntiAlias = true;
  Rect _sizeRect = Rect.zero;

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
    if (size.x != s.x || size.y != s.y) {
      size.setFrom(s);
      _needsComposing = true;
      _sizeRect = Rect.fromLTWH(0, 0, size.x, size.y);
    }
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

    late Rect src;
    late Rect dst;
    final Rect srcCenter = Rect.fromLTWH(
      _grid.left,
      _grid.top,
      _image.width - _grid.left - _grid.right,
      _image.height - _grid.top - _grid.bottom,
    );
    final Rect dstCenter = Rect.fromLTWH(
      _grid.left,
      _grid.top,
      max(0, size.x - _grid.left - _grid.right),
      max(0, size.y - _grid.top - _grid.bottom),
    );

    // Top left corner
    src = Rect.fromLTWH(0, 0, _grid.left, _grid.top);
    _composeStretch(canvas, src, src, paint);

    // Top
    src = Rect.fromLTWH(_grid.left, 0, srcCenter.width, _grid.top);
    dst = Rect.fromLTWH(dstCenter.left, 0, dstCenter.width, src.height);
    switch (repeat.top) {
      case NineGridRepeatType.repeat:
        _composeRepeat(canvas, src, dst, paint);
        break;
      default:
        _composeStretch(canvas, src, dst, paint);
        canvas.drawImageRect(_image, src, dst, paint);
        break;
    }

    // Top right corner
    src = Rect.fromLTWH(srcCenter.right, 0, _grid.right, _grid.top);
    dst = Rect.fromLTWH(dstCenter.right, 0, max(0, size.x - dstCenter.right), dstCenter.top);
    _composeStretch(canvas, src, dst, paint);

    // Left
    src = Rect.fromLTWH(0, srcCenter.top, srcCenter.left, srcCenter.height);
    dst = Rect.fromLTWH(0, dstCenter.top, dstCenter.left, dstCenter.height);
    switch (repeat.left) {
      case NineGridRepeatType.repeat:
        _composeRepeat(canvas, src, dst, paint);
        break;
      default:
        _composeStretch(canvas, src, dst, paint);
        break;
    }

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
    src = Rect.fromLTWH(srcCenter.right, srcCenter.top, _grid.right, srcCenter.height);
    dst = Rect.fromLTWH(dstCenter.right, dstCenter.top, _grid.right, dstCenter.height);
    switch (repeat.right) {
      case NineGridRepeatType.repeat:
        _composeRepeat(canvas, src, dst, paint);
        break;
      default:
        _composeStretch(canvas, src, dst, paint);
        break;
    }

    // Bottom left corner
    src = Rect.fromLTWH(0, srcCenter.bottom, _grid.left, _grid.bottom);
    dst = Rect.fromLTWH(0, dstCenter.bottom, _grid.left, _grid.bottom);
    _composeStretch(canvas, src, dst, paint);

    // Bottom
    src = Rect.fromLTWH(_grid.left, srcCenter.bottom, srcCenter.width, _grid.bottom);
    dst = Rect.fromLTWH(_grid.left, dstCenter.bottom, dstCenter.width, _grid.bottom);
    switch (repeat.top) {
      case NineGridRepeatType.repeat:
        _composeRepeat(canvas, src, dst, paint);
        break;
      default:
        _composeStretch(canvas, src, dst, paint);
        canvas.drawImageRect(_image, src, dst, paint);
        break;
    }

    // Bottom right corner
    src = Rect.fromLTWH(srcCenter.right, srcCenter.bottom, _grid.right, _grid.bottom);
    dst = Rect.fromLTWH(dstCenter.right, dstCenter.bottom, _grid.right, _grid.bottom);
    _composeStretch(canvas, src, dst, paint);

    // Create image
    final picture = recorder.endRecording();
    picture.toImage(size.x.ceil(), size.y.ceil()).then((value) {
      _output = value;
      _isComposing = false;
    });
  }

  void _composeStretch(Canvas canvas, Rect src, Rect dst, Paint paint) {
    if (src.isEmpty || dst.isEmpty) return;
    canvas.drawImageRect(_image, src, dst, paint);
  }

  void _composeRepeat(Canvas canvas, Rect src, Rect dst, Paint paint, [bool stretchX = false, bool stretchY = false]) {
    if (src.isEmpty || dst.isEmpty) return;

    Rect start = Rect.fromLTWH(dst.left, dst.top, stretchX ? dst.width : src.width, stretchY ? dst.height : src.height);
    Rect patch = Rect.fromLTWH(dst.left, dst.top, start.width, start.height);
    int sx = (dst.width / patch.width).ceil();
    int sy = (dst.height / patch.height).ceil();
    for (int y = 0; y < sy; y++) {
      for (int x = 0; x < sx; x++) {
        canvas.drawImageRect(_image, src, patch, paint);
        patch = dst.intersect(Rect.fromLTWH(patch.left + start.width, patch.top, start.width, start.height));
      }
      patch = dst.intersect(Rect.fromLTWH(start.left, patch.top + start.height, start.width, start.height));
    }
  }

  @mustCallSuper
  @override
  void render(Canvas canvas) {
    bool doRender = true;
    if (_needsComposing) {
      compose();
      doRender = false;
    } else if (_isComposing || _output == null || _output?.width == 0 || _output?.height == 0) {
      doRender = false;
    }

    if (doRender) {
      print('render to $_sizeRect');
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
}

class BitmapNineGridComponent extends NineGridComponent with Snap {
  BitmapNineGridComponent(
    Image image,
    Vector2 size, {
    NineGridSize? grid,
    NineGridRepeat? repeat,
  }) : super(
          image,
          size,
          grid: grid,
          repeat: repeat,
        );
}
