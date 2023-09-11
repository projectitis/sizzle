import 'dart:math';

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
        c == dollarSign;
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
        c == percent;
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

  /// Calculate the width of a substring
  double _calculateWidth(int start, int end) {
    final expectedSize = _renderer.getLineMetrics(_text.substring(
      start,
      min(end, _text.length),
    ),);
    _lineHeight = max(_lineHeight, expectedSize.height);
    _actualWidth = max(_actualWidth, expectedSize.width);
    return expectedSize.width;
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

    void addLine(int pos, double offset) {
      _lines.add(TextAreaLine(startPos, pos, offset));
      isBreak = true;
      startPos = pos;
      breakPos = pos;
    }

    int? prepareLine(int pos, [bool forceBreak = false]) {
      double w = _calculateWidth(startPos, pos);
      if (w > _width || forceBreak) {
        if (!forceBreak) {
          w = _calculateWidth(startPos, breakPos);
        }
        double offset = 0;
        if (_align == TextAlign.right || _align == TextAlign.end) {
          offset = _width - w;
        } else if (_align == TextAlign.center) {
          offset = (_width - w) * 0.5;
        }
        addLine(breakPos, offset);
        return breakPos;
      } else {
        breakPos = max(breakPos, pos);
      }
      return null;
    }

    _lines.clear();
    int pos = 0;
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
        addLine(pos, 0);
      }
      // Allow break before
      else if (CharCode.isBreakableBefore(c)) {
        pos = prepareLine(pos - 1) ?? pos;
      }
      // Allow break
      else if (CharCode.isWhitespace(c)) {
        pos = prepareLine(pos - 1) ?? pos;
      }
      // Allow break after
      else if (CharCode.isBreakableAfter(c)) {
        pos = prepareLine(pos) ?? pos;
      }
      // No break
    }
    // Add last line
    //breakPos = pos;
    pos = prepareLine(pos) ?? pos;
    breakPos = pos;
    prepareLine(_text.length, true);

    // Total size
    size.setValues(_actualWidth, _lineHeight * _lines.length);

    /*
    print('Size $_width x ($_lineHeight x ${_lines.length}) = $size');
    for (final l in _lines) {
      print('"${_text.substring(l.start, l.end)}" (${_width - l.offset})');
    }
    */
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
