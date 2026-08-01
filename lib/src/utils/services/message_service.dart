import 'package:flame/components.dart';

import '../services.dart';

/// Message ids raised by Sizzle itself.
///
/// Ids `0`-`999` are **reserved for engine use**. Games should allocate
/// their own ids from `1000` upward so that future Sizzle messages never
/// collide with them. Nothing enforces this — [MessageService] accepts any
/// `int` — it is a convention.
///
/// Each constant is a plain `int`, so it can be passed straight to
/// [MessageService.send] and [MessageService.add]:
///
/// ```dart
/// Services.messages.add(SizzleMessage.noop, (id, args) => true);
/// ```
abstract final class SizzleMessage {
  /// Does nothing. A placeholder so the reserved range has a defined
  /// entry, and a convenient no-op id for tests and default values.
  static const int noop = 0;

  /// A scene has become active. Sent from `Scene.onMount`, so the new
  /// scene is fully live and `Services.game.currentScene` already points
  /// at it.
  ///
  /// `args` is the route name as a `String?` — nullable because Flame's
  /// `Route.name` is only set for named routes.
  ///
  /// A route returned to by popping the navigation stack does not remount,
  /// so no message is sent in that case. `SizzleGame.changeScene` only
  /// ever pushes, so this affects games driving `SizzleGame.router`
  /// directly.
  static const int sceneChanged = 1;

  /// The effective frame rate mode changed. Sent once the new mode is
  /// fully engaged, and only when it actually differs from the previous
  /// one.
  ///
  /// `args` is the new [FrameRateMode]. This is the only way to observe
  /// the asynchronous hardware-rate resolution settling, or a request for
  /// `FrameRateMode.hardwareHalfRate` silently falling back to software or
  /// native.
  static const int frameRateModeChanged = 2;

  /// The application lifecycle state changed - the OS backgrounded,
  /// foregrounded, hid or detached the app.
  ///
  /// `args` is the new `AppLifecycleState`. Backgrounding also pauses the
  /// engine, so expect [gamePaused] alongside this; they are separate
  /// facts, not a double-send.
  static const int appLifecycleChanged = 3;

  /// The game loop was paused. Sent for `pauseEngine()` and for
  /// `game.paused = true`, on the transition only. `args` is `null`.
  ///
  /// Not sent when [FrameRateMode.softwareHalfRate] pauses the ticker as
  /// an implementation detail - the title itself did not pause.
  static const int gamePaused = 4;

  /// The game loop resumed. Sent for `resumeEngine()` and for
  /// `game.paused = false`, on the transition only. `args` is `null`.
  ///
  /// Not sent when a frame rate mode change resumes the ticker
  /// internally. See [gamePaused].
  static const int gameResumed = 5;
}

/// Signature for a message listener registered with [MessageService.add].
///
/// Receives the message [id] that was sent and the sender's `args` payload
/// (`null` when the sender supplied none). Return `true` to stay
/// registered, or `false` to remove the listener after this call.
typedef MessageCallback = bool Function(int id, dynamic args);

/// Handle to a listener registered on [MessageService]. The service owns
/// the instance; callers receive it from [MessageService.add] and use it to
/// inspect state, [pause]/[resume], or [cancel].
class MessageListener {
  MessageListener._(this._service, this.id, this.callback);

  final MessageService _service;

  /// The message id this listener is registered against.
  final int id;

  /// The function invoked when [id] is sent.
  final MessageCallback callback;

  bool _removed = false;
  bool _paused = false;

  /// `true` until the listener is removed, either by [cancel], by
  /// returning `false` from [callback], or by a bulk
  /// [MessageService.clear].
  bool get isActive => !_removed;

  /// `true` while paused by [pause]. A paused listener stays registered
  /// but is skipped during dispatch.
  bool get isPaused => _paused;

  /// Suspend delivery without unregistering. Has no effect once the
  /// listener has been removed.
  void pause() {
    if (!_removed) _paused = true;
  }

  /// Resume delivery to a [pause]d listener. No-op if not paused.
  void resume() {
    _paused = false;
  }

  /// Unregister the listener. Safe to call from inside any callback,
  /// including during the dispatch this listener is part of. Idempotent.
  void cancel() {
    _service._cancel(this);
  }
}

/// A synchronous publish/subscribe hub keyed by `int` message id.
///
/// Consumers register a [MessageCallback] against an id with [add]; any
/// other consumer can then [send] that id without knowing who is
/// listening. Dispatch is immediate — [send] invokes every live listener
/// inline and returns once they have all run. There is no queue, no
/// per-send allocation and no update tick.
///
/// ```dart
/// // Somewhere that cares about the player dying
/// Services.messages.add(Msg.playerDied, (id, args) {
///   lives -= 1;
///   return lives > 0; // unregister once out of lives
/// });
///
/// // Somewhere that kills the player
/// Services.messages.send(Msg.playerDied, deathCause);
/// ```
///
/// Returning `false` from a callback removes that listener. For removal
/// from outside the callback, keep the [MessageListener] returned by [add]
/// and call `cancel()`, or use [remove].
///
/// Ids may be any `int`, but **`0`-`999` are reserved for Sizzle** (see
/// [SizzleMessage]). Allocate game ids from `1000` upward. This is a
/// convention only; it is not enforced.
///
/// Listener lists are never mutated while a dispatch is in flight, so it
/// is safe to call [add], [remove], [send] and [MessageListener.cancel]
/// from inside a callback. See [send] for the exact ordering guarantees.
class MessageService {
  final Map<int, List<MessageListener>> _listeners =
      <int, List<MessageListener>>{};

  /// Ids whose lists have flagged removals awaiting compaction. Only
  /// populated while a dispatch is in flight.
  final Set<int> _dirty = <int>{};

  /// Nesting depth of the current [send]. Zero when idle.
  int _depth = 0;

  /// Register [callback] against message [id]. Returns a
  /// [MessageListener] handle the caller can store to pause, resume or
  /// cancel the registration.
  ///
  /// The same callback may be registered more than once against the same
  /// id; each registration is independent and fires separately.
  ///
  /// Registering from inside a callback is safe. The new listener does
  /// *not* receive the message currently being dispatched — it becomes
  /// eligible on the next [send].
  MessageListener add(int id, MessageCallback callback) {
    final MessageListener listener = MessageListener._(this, id, callback);
    (_listeners[id] ??= <MessageListener>[]).add(listener);
    return listener;
  }

  /// Remove the first live listener on [id] whose callback equals
  /// [callback]. Returns `true` if one was found and removed.
  ///
  /// Where the same callback has been registered against [id] more than
  /// once, only the earliest registration is removed. Prefer holding the
  /// [MessageListener] from [add] when the distinction matters.
  bool remove(int id, MessageCallback callback) {
    final List<MessageListener>? list = _listeners[id];
    if (list == null) return false;
    for (int i = 0; i < list.length; i++) {
      final MessageListener listener = list[i];
      // Compared with `==`, not `identical`: two tear-offs of the same
      // instance method are equal but not necessarily identical.
      if (!listener._removed && listener.callback == callback) {
        _cancel(listener);
        return true;
      }
    }
    return false;
  }

  /// Send message [id], invoking every live listener registered against it
  /// with `(id, args)`. Returns the number of listeners invoked.
  ///
  /// The optional [args] payload is passed straight through by reference —
  /// every listener receives the *same* instance, so treat it as
  /// read-only. Mutating it is visible to listeners that run after.
  ///
  /// Guarantees:
  ///
  /// - Listeners are invoked in registration order.
  /// - A listener returning `false` is removed and will not be invoked
  ///   again.
  /// - Listeners added during this dispatch do not receive this message.
  /// - Listeners cancelled during this dispatch are skipped, even if they
  ///   had not yet been reached.
  /// - Nested sends of the same id are permitted and will not disturb the
  ///   outer dispatch.
  ///
  /// Sending an id with no listeners is free and returns `0`.
  int send(int id, [dynamic args]) {
    final List<MessageListener>? list = _listeners[id];
    if (list == null || list.isEmpty) return 0;

    // Snapshot the length so listeners appended during dispatch are not
    // reached. Indices below this stay valid because compaction is
    // deferred until the outermost dispatch unwinds.
    final int count = list.length;
    int fired = 0;
    _depth++;
    for (int i = 0; i < count; i++) {
      final MessageListener listener = list[i];
      if (listener._removed || listener._paused) continue;
      fired++;
      if (!listener.callback(id, args)) {
        listener._removed = true;
        _dirty.add(id);
      }
    }
    _depth--;
    if (_depth == 0 && _dirty.isNotEmpty) _sweep();
    return fired;
  }

  /// Remove every listener registered against [id], or every listener on
  /// every id when [id] is omitted.
  ///
  /// Safe to call from inside a callback; the removals take effect
  /// immediately for dispatch purposes, and the lists are compacted once
  /// the current dispatch unwinds.
  void clear([int? id]) {
    if (id == null) {
      for (final List<MessageListener> list in _listeners.values) {
        for (int i = 0; i < list.length; i++) {
          list[i]._removed = true;
        }
      }
      if (_depth == 0) {
        _listeners.clear();
        _dirty.clear();
      } else {
        _dirty.addAll(_listeners.keys);
      }
      return;
    }

    final List<MessageListener>? list = _listeners[id];
    if (list == null) return;
    for (int i = 0; i < list.length; i++) {
      list[i]._removed = true;
    }
    if (_depth == 0) {
      list.clear();
    } else {
      _dirty.add(id);
    }
  }

  /// Number of live listeners registered against [id], or across every id
  /// when [id] is omitted. Excludes listeners that have been cancelled but
  /// not yet compacted away. Paused listeners are counted.
  int count([int? id]) {
    int total = 0;
    if (id == null) {
      for (final List<MessageListener> list in _listeners.values) {
        for (int i = 0; i < list.length; i++) {
          if (!list[i]._removed) total++;
        }
      }
      return total;
    }
    final List<MessageListener>? list = _listeners[id];
    if (list == null) return 0;
    for (int i = 0; i < list.length; i++) {
      if (!list[i]._removed) total++;
    }
    return total;
  }

  /// Flag [listener] as removed. While a dispatch is in flight the entry
  /// stays in place — only the flag is set — so live indices remain valid;
  /// the list is compacted once the outermost [send] unwinds.
  void _cancel(MessageListener listener) {
    if (listener._removed) return;
    listener._removed = true;
    final List<MessageListener>? list = _listeners[listener.id];
    if (list == null) return;
    if (_depth == 0) {
      list.remove(listener);
    } else {
      _dirty.add(listener.id);
    }
  }

  /// Compact the lists of every id flagged during a dispatch. Empty lists
  /// are retained so re-registering a known id does not reallocate.
  void _sweep() {
    for (final int id in _dirty) {
      _listeners[id]?.removeWhere((MessageListener l) => l._removed);
    }
    _dirty.clear();
  }
}

/// Mixin for [Component]s that listen for messages, tying listener
/// lifetime to component lifetime.
///
/// Registrations made through [listen] are cancelled automatically in
/// [onRemove]. Without this, a listener registered by a scene outlives the
/// scene — [MessageService] is a static singleton and knows nothing about
/// the component tree.
///
/// ```dart
/// class HudScene extends Scene with HasMessages {
///   @override
///   Future<void> onLoad() async {
///     listen(Msg.scoreChanged, (id, args) {
///       label.text = 'Score: $args';
///       return true;
///     });
///   }
/// }
/// ```
mixin HasMessages on Component {
  final List<MessageListener> _messageListeners = <MessageListener>[];

  /// The [MessageService] to register against. Defaults to the global
  /// `Services.messages`; override to target a different instance.
  MessageService get messageService => Services.messages;

  /// Register [callback] against message [id] for as long as this
  /// component is mounted. Same semantics as [MessageService.add], but the
  /// listener is cancelled automatically when the component is removed.
  MessageListener listen(int id, MessageCallback callback) {
    final MessageListener listener = messageService.add(id, callback);
    _messageListeners.add(listener);
    return listener;
  }

  @override
  void onRemove() {
    for (int i = 0; i < _messageListeners.length; i++) {
      _messageListeners[i].cancel();
    }
    _messageListeners.clear();
    super.onRemove();
  }
}
