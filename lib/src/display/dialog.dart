import 'dart:async';
import 'dart:math';

import 'package:jenny/jenny.dart';
import 'package:flame/events.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/material.dart';

import 'package:sizzle/src/text/text.dart';
import 'package:sizzle/src/display/sprite.dart';

/// Options available to the speech bubble
class DialogOptions {
  bool displayCharacterName = false;
  //bool displayCharacterAvatar = false;
  bool tapAnywhereToAdvanceDialog = true;
  //bool useIconsForChoices = false;
  double paddingBetweenChoices = 0;
}

/// A dialog style definition
class DialogStyle {
  String name;
  String spriteName;
  EdgeInsets grid;
  EdgeInsets padding;
  Anchor anchor;

  DialogStyle(
    this.name, {
    required this.spriteName,
    required this.grid,
    required this.padding,
    required this.anchor,
  });
}

/// A dialog text style definition
class DialogTextStyle {
  String name;
  late TextStyle captionStyle;
  TextStyle textStyle;

  DialogTextStyle(
    this.name, {
    required this.textStyle,
    TextStyle? captionStyle,
    TextStyle? selectedTextStyle,
  }) : captionStyle = captionStyle ?? textStyle;
}

/// Text dialog (speech bubble)
///
/// Uses yarn spinner to process and display conversation. Add
/// a component to the tree, then pass it to `Services.startDialog`.
class DialogComponent extends PositionComponent with DialogueView, Snap, TapCallbacks, Hoverable {
  Vector2 dialogSize;
  bool showing = false;
  Snap? _trackTarget;
  final List<String> characters = [];
  final Map<String, DialogStyle> _dialogStyles = {};
  final Map<String, DialogTextStyle> _textStyles = {};
  late DialogStyle _activeDialogStyle;
  final Map<String, Sprite> _backgrounds = {};
  Completer<bool> _lineCompleter = Completer();
  Completer<int> _choiceCompleter = Completer();

  final DialogOptions options = DialogOptions();
  late NineTileBoxComponent _bg;
  final List<TextArea> _text = [];

  /// Called by the dialog to locate a character in the scene
  /// so that the bubble can be positioned correctly.
  Snap? Function(String)? onFindCharacterPosition;

  /// Called by the dialog when a dialog session starts.
  void Function(void)? onStart;

  /// Called by the dialog when a dialog session ends.
  void Function(void)? onFinish;

  /// The `dialogSize` dictates the maximum width and height of the
  /// dialog box.
  ///
  /// At least one dialog style and one text style must be passed in.
  /// These are usually given the name 'default'. Styles are changed
  /// by adding a tag to the dialog that matches the style name. For
  /// example, you might have a style for 'thinking' that shows as a
  /// thought bubble instead of a speech bubble. Example:
  /// Bob: Has she really not seen me? #thinking
  ///
  /// Any line or choice that does not contain a matching tag will use
  /// the 'default' style if it exists, otherwise the first style passed
  /// in will be used as the default.
  ///
  /// There are two special styles: 'default' is the default style in
  /// all cases that no other style is set. 'choice' is the default
  /// style for choices. If 'choice' is not set, 'default' is used.
  ///
  /// It is possible to use two different DialogComponents for
  /// different characters in the scene. In order ro do this, pass
  /// is a list of 'characters' that this dialog should display for.
  ///
  /// The 'anchor' is used as the attachment point for the dialog.
  ///
  /// The dialog will call 'onFindCharacterPosition' to request the
  /// component that should be aligned to. If this callback is not
  /// implemented, the dialog 'position' must be set instead.
  ///
  /// TODO: If there is too much text for the height, allow the user
  /// to click through the full text.
  DialogComponent({
    required this.dialogSize,
    required List<DialogStyle> dialogStyles,
    required List<DialogTextStyle> textStyles,
  }) : super(size: dialogSize) {
    assert(dialogStyles.isNotEmpty, 'At least one dialog style must be provided');
    assert(textStyles.isNotEmpty, 'At least one text style must be provided');
    anchorWindow = AnchorWindow.viewWindow;
    for (final s in dialogStyles) {
      assert(s.name != '', 'A dialog style must have a name');
      assert(!_dialogStyles.containsKey(s.name), 'All dialog styles must have a unique name');
      _dialogStyles[s.name] = s;
    }
    _activeDialogStyle = _dialogStyles['default'] ?? _dialogStyles.entries.first.value;
    for (final s in textStyles) {
      assert(s.name != '', 'A text style must have a name');
      assert(!_textStyles.containsKey(s.name), 'All text styles must have a unique name');
      _textStyles[s.name] = s;
    }
    anchor = _activeDialogStyle.anchor;
  }

  @override
  FutureOr<void> onLoad() async {
    // Load all background sprites and cache them
    for (final s in _dialogStyles.values) {
      if (!_backgrounds.containsKey(s.spriteName)) {
        final sprite = await Sprite.load(s.spriteName);
        _backgrounds[s.spriteName] = sprite;
      }
    }
    _bg = NineTileBoxComponent(
        nineTileBox: NineTileBox.withGrid(
          _backgrounds[_activeDialogStyle.spriteName]!,
          leftWidth: _activeDialogStyle.grid.left,
          rightWidth: _activeDialogStyle.grid.right,
          topHeight: _activeDialogStyle.grid.top,
          bottomHeight: _activeDialogStyle.grid.bottom,
        ),
        size: dialogSize);

    return super.onLoad();
  }

  FutureOr<void> _show() async {
    if (showing) return;
    showing = true;
    await loaded;

    bitmapPosition.setFrom(position);

    // Change style
    if (_bg.isMounted) {
      await _bg.removed;
    }
    add(_bg);
  }

  void _hide() {
    if (!showing) return;
    showing = false;
    _clearTextAreas();
    remove(_bg);
    _trackTarget = null;
    game.mouseCursor = SystemMouseCursors.basic;
  }

  @override
  FutureOr<void> onDialogueStart() {
    onStart?.call;
    return super.onDialogueStart();
  }

  @override
  FutureOr<void> onDialogueFinish() {
    onFinish?.call;
    return super.onDialogueFinish();
  }

  DialogTextStyle _setStyles(List<String> tags, bool choice) {
    String styleName = 'default';
    for (final t in tags) {
      if (_dialogStyles.containsKey(t)) {
        styleName = t;
        break;
      }
    }
    if (styleName == 'default') {
      if (choice && _dialogStyles.containsKey('choice')) {
        styleName = 'choice';
      } else if (!_dialogStyles.containsKey('default')) {
        styleName = _dialogStyles.entries.first.key;
      }
    }
    if (_dialogStyles.containsKey(styleName) && _activeDialogStyle.name != styleName) {
      _activeDialogStyle = _dialogStyles[styleName]!;
      _bg.nineTileBox = NineTileBox.withGrid(
        _backgrounds[_activeDialogStyle.spriteName]!,
        leftWidth: _activeDialogStyle.grid.left,
        rightWidth: _activeDialogStyle.grid.right,
        topHeight: _activeDialogStyle.grid.top,
        bottomHeight: _activeDialogStyle.grid.bottom,
      );
    }

    DialogTextStyle? textStyle;
    for (final t in tags) {
      if (_textStyles.containsKey(t)) {
        textStyle = _textStyles[t];
        break;
      }
    }
    textStyle ??= (_textStyles['default'] ?? _textStyles.entries.first.value);
    return textStyle;
  }

  @override
  FutureOr<bool> onLineStart(DialogueLine line) async {
    if (line.character == null || (characters.isNotEmpty && !characters.contains(line.character?.name))) {
      return true;
    }

    await _show();
    DialogTextStyle textStyle = _setStyles(line.tags, false);

    if (options.displayCharacterName) {
      _addTextArea(textStyle.captionStyle, line.character!.name);
    }
    _trackTarget = onFindCharacterPosition?.call(line.character!.name);
    if (_trackTarget != null) {
      anchorWindow = _trackTarget!.anchorWindow;
      _updatePosition();
    }
    _addTextArea(textStyle.textStyle, line.text);
    _prepare(false);

    _lineCompleter = Completer();
    return _lineCompleter.future;
  }

  @override
  FutureOr<void> onLineFinish(DialogueLine line) {
    _hide();
  }

  @override
  FutureOr<int?> onChoiceStart(DialogueChoice choice) async {
    for (final option in choice.options) {
      bool characterMatches = true;
      if (option.character == null || (characters.isNotEmpty && !characters.contains(option.character?.name))) {
        characterMatches = false;
      }
      if (option.isAvailable && characterMatches) {
        await _show();

        DialogTextStyle textStyle = _setStyles(option.tags, true);
        if (option == choice.options.first) {
          if (options.displayCharacterName) {
            _addTextArea(textStyle.captionStyle, option.character!.name);
          }
          _trackTarget = onFindCharacterPosition?.call(option.character!.name);
          if (_trackTarget != null) {
            anchorWindow = _trackTarget!.anchorWindow;
            _updatePosition();
          }
        }
        _addTextArea(textStyle.textStyle, option.text);
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
    _hide();
  }

  void _clearTextAreas() {
    for (final t in _text) {
      _bg.remove(t);
    }
    _text.clear();
  }

  /// Add a new text area to the bubble
  /// TODO: Object pooling?
  void _addTextArea(TextStyle style, String s, {Color? color}) {
    final t = TextArea(
      text: s,
      maxWidth: dialogSize.x - _activeDialogStyle.padding.left - _activeDialogStyle.padding.right,
      style: color != null ? style.copyWith(color: color) : style,
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
        t.bitmapPosition.setFrom(_activeDialogStyle.padding.topLeft.toVector2());
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
      actualSize.x + _activeDialogStyle.padding.left + _activeDialogStyle.padding.right,
      actualSize.y + _activeDialogStyle.padding.top + _activeDialogStyle.padding.bottom,
    );
    size.setFrom(_bg.size);
  }

  @override
  bool onHoverEnter(PointerHoverInfo info) {
    game.mouseCursor = SystemMouseCursors.click;
    return super.onHoverEnter(info);
  }

  @override
  bool onHoverLeave(PointerHoverInfo info) {
    game.mouseCursor = SystemMouseCursors.basic;
    return super.onHoverLeave(info);
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
        if ((event.localPosition.y >= t.position.y) && (event.localPosition.y < (t.position.y + t.height))) {
          _choiceCompleter.complete(index);
        }
        index = index + 1;
      }
    }
  }

  void _updatePosition() {
    if (showing && _trackTarget != null) {
      bitmapPosition.x = _trackTarget!.position.x / game.bitmapScale.x + _trackTarget!.size.x * 0.5;
      bitmapPosition.y = _trackTarget!.position.y / game.bitmapScale.y;
    }
  }

  @override
  void update(double dt) {
    _updatePosition();
    super.update(dt);
  }
}
