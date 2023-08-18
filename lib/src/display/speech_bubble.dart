import 'dart:async';
import 'dart:math';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:jenny/jenny.dart';
import 'package:sizzle/src/text/text.dart';
import 'package:sizzle/src/display/sprite.dart';
import 'package:sizzle/src/game/services.dart';

/// Options available to the speech bubble
class SpeechBubbleOptions {
  bool displayCharacterName = false;
  bool displayCharacterAvatar = false;
  bool tapAnywhereToAdvanceDialog = true;
  bool useIconsForChoices = false;
  double paddingBetweenChoices = 0;
}

/// Show a text dialog
class SpeechBubbleComponent extends PositionComponent with DialogueView, Snap, TapCallbacks {
  Vector2 dialogSize;
  EdgeInsets dialogGrid;
  bool showing = false;
  Snap? _trackTarget;
  EdgeInsets textMargins;
  TextStyle? captionStyle;
  TextStyle textStyle;
  List<String> characters;
  Completer<void> _loadCompleter = Completer();
  Completer<bool> _lineCompleter = Completer();
  Completer<int> _choiceCompleter = Completer();

  final SpeechBubbleOptions options = SpeechBubbleOptions();

  String dialogSpriteName;
  late NineTileBoxComponent _bg;
  final List<TextArea> _text = [];

  /// Called by the speech bubble to locate a character in the scene
  /// so that the bubble can be positioned correctly.
  Snap? Function(String)? onFindCharacterPosition;

  /// Called when the dialog has ended and the bubble is closed, or
  /// when the bubble is dismissed by the user (if applicable).
  void Function()? onHide;

  SpeechBubbleComponent(this.dialogSpriteName,
      {required this.dialogGrid,
      required this.dialogSize,
      required this.textMargins,
      required this.textStyle,
      this.captionStyle,
      this.characters = const [],
      super.anchor})
      : super(size: dialogSize) {
    captionStyle ??= textStyle;
    anchorWindow = AnchorWindow.viewWindow;
  }

  @override
  FutureOr<void> onLoad() async {
    print('SpeechBubbleComponent::onLoad');
    final sprite = await Sprite.load(dialogSpriteName);
    final bgTiles = NineTileBox.withGrid(
      sprite,
      leftWidth: dialogGrid.left,
      rightWidth: dialogGrid.right,
      topHeight: dialogGrid.top,
      bottomHeight: dialogGrid.bottom,
    );
    _bg = NineTileBoxComponent(nineTileBox: bgTiles, size: dialogSize);

    _loadCompleter.complete();
    return super.onLoad();
  }

  FutureOr<void> _show() async {
    print('SpeechBubbleComponent::_show');
    if (showing) return;
    await _loadCompleter.future;

    showing = true;
    bitmapPosition.setFrom(position);

    if (_bg.isMounted) {
      await _bg.removed;
    }
    add(_bg);
  }

  void _hide() {
    print('SpeechBubbleComponent::_hide');
    if (!showing) return;
    showing = false;
    _clearTextAreas();
    remove(_bg);
    _trackTarget = null;
    onHide?.call();
  }

  @override
  FutureOr<bool> onLineStart(DialogueLine line) async {
    print('SpeechBubbleComponent::onLineStart');
    if (line.character == null || (characters.isNotEmpty && !characters.contains(line.character?.name))) {
      if (line.character == null) {
        print('  character is null');
      } else {
        print('  character is ${line.character!.name}. Not in $characters');
      }
      return true;
    }

    await _show();
    if (options.displayCharacterName) {
      print('Adding text area for character name');
      _addTextArea(captionStyle!, line.character!.name, Colors.black);
    }
    _trackTarget = onFindCharacterPosition?.call(line.character!.name);
    if (_trackTarget != null) {
      anchorWindow = _trackTarget!.anchorWindow;
    }
    print('Adding text area for line: ${line.text}');
    _addTextArea(textStyle, line.text, Colors.black);
    _prepare(false);

    _lineCompleter = Completer();
    return _lineCompleter.future;
  }

  @override
  FutureOr<void> onLineFinish(DialogueLine line) {
    print('SpeechBubbleComponent::onLineFinish');
    _hide();
  }

  @override
  FutureOr<int?> onChoiceStart(DialogueChoice choice) async {
    print('SpeechBubbleComponent::onChoiceStart');
    for (final option in choice.options) {
      bool characterMatches = true;
      if (option.character == null || (characters.isNotEmpty && !characters.contains(option.character?.name))) {
        characterMatches = false;
      }
      if (option.isAvailable && characterMatches) {
        await _show();

        if (option == choice.options.first) {
          if (options.displayCharacterName) {
            _addTextArea(captionStyle!, option.character!.name, Colors.black);
          }
          _trackTarget = onFindCharacterPosition?.call(option.character!.name);
          if (_trackTarget != null) {
            anchorWindow = _trackTarget!.anchorWindow;
          }
        }
        _addTextArea(textStyle, option.text, Colors.black);
      }
    }
    if (showing) {
      _prepare(true);

      _choiceCompleter = Completer();
      return _choiceCompleter.future;
    }
    return null;
  }

  @override
  FutureOr<void> onChoiceFinish(DialogueOption option) {
    print('SpeechBubbleComponent::onChoiceFinish');
    _hide();
  }

  void _clearTextAreas() {
    print('SpeechBubbleComponent::_clear');
    for (final t in _text) {
      _bg.remove(t);
    }
    _text.clear();
  }

  /// Add a new text area to the bubble
  /// TODO: Object pooling?
  void _addTextArea(TextStyle style, String s, Color c) {
    //print('Color 0x${c.value.toRadixString(16)}');
    final t = TextArea(
      text: s,
      maxWidth: dialogSize.x - textMargins.left - textMargins.right,
      style: style.copyWith(color: c),
    )..useBitmapScale = false;
    _bg.add(t);
    _text.add(t);
  }

  /// Arrange text areas correctly within the bubble and resize
  /// the background to fit them.
  void _prepare(bool choices) {
    TextArea? lt;
    Vector2 actualSize = Vector2.zero();
    for (final t in _text) {
      if (t == _text.first) {
        t.bitmapPosition.setFrom(textMargins.topLeft.toVector2());
      }
      t.prepare();
      actualSize.x = max(actualSize.x, t.size.x);
      actualSize.y += t.size.y;
      if (lt != null) {
        t.bitmapPosition.x = lt.bitmapPosition.x;
        t.bitmapPosition.y = lt.bitmapPosition.y + lt.size.y + options.paddingBetweenChoices;
        actualSize.y += options.paddingBetweenChoices;
      }
      lt = t;
    }
    _bg.size.setValues(
      actualSize.x + textMargins.left + textMargins.right,
      actualSize.y + textMargins.top + textMargins.bottom,
    );
    size.setFrom(_bg.size);
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (!_lineCompleter.isCompleted) {
      _lineCompleter.complete(true);
    } else if (!_choiceCompleter.isCompleted) {
      int index = 0;
      for (final t in _text) {
        if (t == _text.first && options.displayCharacterName) {
          continue;
        }
        if ((event.localPosition.y >= t.y) && (event.localPosition.y < (t.y + t.height))) {
          _choiceCompleter.complete(index);
        }
        index = index + 1;
      }
    }
  }

  @override
  void update(double dt) {
    if (showing && _trackTarget != null) {
      bitmapPosition.x = _trackTarget!.position.x / game.bitmapScale.x + _trackTarget!.size.x * 0.5;
      bitmapPosition.y = _trackTarget!.position.y / game.bitmapScale.y;
    }
    super.update(dt);
  }
}
