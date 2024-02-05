import 'dart:math' show max, min;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';
import 'package:sizzle/src/display/snap.dart';

/// Details of a line of text
class TextAreaLine {
  int start = 0;
  int end = 0;
  double offset;

  TextAreaLine(this.start, this.end, this.offset);
}

/// Character codes
class CharCode {
  static const tab = 9;
  static const newline = 10;
  static const lineFeed = 12;
  static const carriageReturn = 13;
  static const space = 32;
  static const exclamationMark = 33;
  static const doubleQuote = 34;
  static const hash = 35;
  static const dollarSign = 36;
  static const percent = 37;
  static const ampersand = 38;
  static const singleQuote = 39;
  static const bracketOpen = 40;
  static const bracketClose = 41;
  static const asterisk = 42;
  static const plus = 43;
  static const comma = 44;
  static const minus = 45;
  static const period = 46;
  static const forwardSlash = 47;
  static const colon = 58;
  static const semicolon = 59;
  static const lessThan = 60;
  static const equals = 61;
  static const greaterThan = 62;
  static const questionMark = 63;
  static const at = 64;
  static const squareBracketOpen = 91;
  static const backSlash = 92;
  static const squareBracketClose = 93;
  static const hat = 94;
  static const underscore = 95;
  static const grave = 96;
  static const braceOpen = 123;
  static const pipe = 124;
  static const braceClose = 125;
  static const tilde = 126;

  static bool isWhitespace(int c) {
    return c < 33;
  }

  static bool isBreakableBefore(int c) {
    return c == braceOpen ||
        c == bracketOpen ||
        c == squareBracketOpen ||
        c == dollarSign ||
        isWhitespace(c);
  }

  static bool isBreakableAfter(int c) {
    return c == period ||
        c == comma ||
        c == colon ||
        c == semicolon ||
        c == questionMark ||
        c == exclamationMark ||
        c == braceClose ||
        c == bracketClose ||
        c == squareBracketClose ||
        c == percent ||
        c == minus;
  }
}

/// Text area
class TextAreaComponent extends PositionComponent {
  TextPaint _renderer;
  bool _needsPrepare = true;
  final List<TextAreaLine> _lines = [];
  TextAlign _align;
  set align(TextAlign a) {
    if (a == _align) return;
    _align = a;
    _needsPrepare = true;
  }

  String _text = '';
  String get text => _text;
  set text(String s) {
    if (s == _text) return;
    _text = s;
    _needsPrepare = true;
  }

  double _lineHeight = 0;
  double _actualWidth = 0;
  double _width;
  double get maxWidth => _width;
  set maxWidth(double w) {
    if (w == _width) return;
    _width = w;
    _needsPrepare = true;
  }

  set style(TextStyle s) {
    _renderer = TextPaint(style: s);
    _needsPrepare = true;
  }

  set color(Color c) {
    _renderer = TextPaint(style: _renderer.style.copyWith(color: c));
    _needsPrepare = true;
  }

  /// Create a new text area with a fixed [maxWidth] and the given [style].
  /// The text can be aligned left, right or center with [align].
  TextAreaComponent({
    String? text,
    required TextStyle style,
    required double maxWidth,
    TextAlign align = TextAlign.left,
  })  : _width = maxWidth,
        _align = align,
        _renderer = TextPaint(style: style) {
    if (text != null) _text = text;
  }

  /// Recalculate and redraw string
  void dirty() {
    _needsPrepare = true;
  }

  /// Calculate each line of the text area
  void prepare() {
    if (!_needsPrepare) return;
    _needsPrepare = false;
    _lineHeight = 0;
    _actualWidth = 0;
    int startPos = 0;
    int breakPos = 0;
    bool isBreak = false;
    int pos = 0;
    double width = 0;
    double widthAtBreakPos = 0;

    void addLine() {
      double offset = 0;
      if (_align == TextAlign.right || _align == TextAlign.end) {
        offset = _width - widthAtBreakPos;
      } else if (_align == TextAlign.center) {
        offset = (_width - widthAtBreakPos) * 0.5;
      }
      _lines.add(TextAreaLine(startPos, breakPos, offset));
      isBreak = true;
      pos = breakPos;
      startPos = pos;
      _actualWidth = max(_actualWidth, widthAtBreakPos);
      width = 0;
      widthAtBreakPos = 0;
    }

    _lines.clear();
    while (pos < _text.length) {
      int c = _text.codeUnitAt(pos++);

      // After break, ignore leading whitespace
      if (isBreak && CharCode.isWhitespace(c)) {
        startPos++;
        continue;
      }
      isBreak = false;

      // Force break
      if (c == CharCode.newline) {
        addLine();
      }
      // Allow break before
      else if (CharCode.isBreakableBefore(c)) {
        breakPos = pos - 1;
        widthAtBreakPos = width;
      }

      // Break line if too long
      final charSize = _renderer.getLineMetrics(String.fromCharCode(c));
      width += charSize.width;
      _lineHeight = max(_lineHeight, charSize.height);
      if (width >= _width) {
        addLine();
        startPos = pos;
      }

      // Allow break after
      if (CharCode.isBreakableAfter(c)) {
        breakPos = pos;
        widthAtBreakPos = width;
      }
    }
    // Add last line
    if (!isBreak) {
      breakPos = pos;
      widthAtBreakPos = width;
      addLine();
    }

    // Total size
    size.setValues(_actualWidth, _lineHeight * _lines.length);
  }

  @override
  void render(Canvas canvas) {
    prepare();
    Vector2 pos = Vector2.zero();
    for (final line in _lines) {
      if (line.end > line.start + 1) {
        pos.x = line.offset;
        _renderer.render(canvas, text.substring(line.start, line.end), pos);
      }
      pos.y += _lineHeight;
    }
  }
}

class SnapTextAreaComponent extends TextAreaComponent with Snap {
  SnapTextAreaComponent({
    String? text,
    required TextStyle style,
    required double maxWidth,
    TextAlign align = TextAlign.left,
  }) : super(
          text: text,
          style: style,
          maxWidth: maxWidth,
          align: align,
        );
}
