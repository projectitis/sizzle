# Memory pooling

[:arrow_left: Back to documentation](index.md)

- [What is memory pooling?](#what-is-memory-pooling)
- [When to pool](#when-to-pool)
- [Using the pool](#using-the-pool)
- [Resetting objects](#resetting-objects)
- [Inspecting the pool](#inspecting-the-pool)


## What is memory pooling?

A memory pool keeps a stash of already-allocated objects so they can be reused
instead of being thrown away. When you need an object you "borrow" one from
the pool; when you're done you "return" it. The pool only allocates a new
object when the stash is empty.

In a game loop, allocations are surprisingly expensive. Every short-lived
object - a particle, a hitbox check result, a temporary `Vector2`, a tween
parameter - has to be created, tracked, and eventually collected by the
garbage collector. When the GC runs, it can stall the frame long enough that
the user notices a stutter, especially on lower-end mobile devices.

Pooling avoids this in two ways:

- **Fewer allocations.** Reusing objects keeps total allocations close to
  the steady-state number of live objects rather than growing with every
  frame.
- **Predictable GC pressure.** Long-lived pooled objects don't churn through
  generational GC, so collection pauses stay short and rare.

For objects that are created and destroyed by the hundreds per frame -
particles, projectiles, transient vector math - pooling is one of the
cheapest performance wins available.


## When to pool

Pool when an object is:

- short-lived,
- allocated frequently (each frame, in inner loops, etc.),
- and cheap to "reset" back to a clean state.

Don't bother pooling singletons, long-lived game state, or objects that are
expensive or stateful enough that resetting them is harder than just
constructing a new one. A pool that's only borrowed from once isn't doing
anything useful.


## Using the pool

Sizzle provides a [`Pool<T>`](../lib/src/utils/pool.dart#:~:text=class+Pool)
class and a [`Pooled`](../lib/src/utils/pool.dart#:~:text=mixin+Pooled) mixin.
Any class you want to pool must mix in `Pooled`:

```dart
import 'package:sizzle/sizzle.dart';

class Particle with Pooled {
    double x = 0;
    double y = 0;
    double life = 1.0;

    @override
    void reset() {
        x = 0;
        y = 0;
        life = 1.0;
    }
}
```

Create a pool by passing in a creator function. A `static` field on the class
itself is a convenient place to keep it:

```dart
class Particle with Pooled {
    static final Pool<Particle> pool = Pool<Particle>(Particle.new);

    // ...
}
```

Borrow an object from the pool with `get`, and return it with `add`:

```dart
// Borrow an object - allocates a new one if the pool is empty
final p = Particle.pool.get();
p.x = 100;
p.y = 50;

// ... use the particle ...

// Return it to the pool when done
Particle.pool.add(p);
```

If you just want to use the pool without checking the source code, the methods
on `Pool<T>` are:

- [`get()`](../lib/src/utils/pool.dart#:~:text=T+get) - borrow an object,
  creating a new one if the pool is empty
- [`add(obj)`](../lib/src/utils/pool.dart#:~:text=void+add) - return an object
  to the pool (calls `reset()` automatically)
- [`clear()`](../lib/src/utils/pool.dart#:~:text=void+clear) - release every
  pooled object so they can be garbage collected


## Resetting objects

When an object is returned via `add`, the pool calls its `reset()` method
before storing it. This is your chance to wipe any per-use state so the next
borrower gets a clean object.

The default `reset()` on the `Pooled` mixin is a no-op, so you only need to
override it for fields that need clearing. Be thorough: a stale field left
behind by a previous user is a classic source of "spooky" bugs that only
surface once the pool starts reusing objects.

```dart
class Bullet with Pooled {
    Vector2 position = Vector2.zero();
    Vector2 velocity = Vector2.zero();
    Entity? owner;
    bool isActive = false;

    @override
    void reset() {
        position.setZero();
        velocity.setZero();
        owner = null;
        isActive = false;
    }
}
```

Note that `reset()` is called when the object is **returned** to the pool, not
when it's borrowed. If you also need per-borrow setup (e.g. assigning fresh
values), do that at the call site after `get()`.


## Inspecting the pool

Two read-only fields are useful for tuning and diagnostics:

- [`length`](../lib/src/utils/pool.dart#:~:text=get+length) - how many objects
  are currently sitting in the pool, ready to be borrowed
- [`created`](../lib/src/utils/pool.dart#:~:text=get+created) - how many
  objects the pool has ever allocated, whether or not they are currently
  inside it

If `created` keeps climbing during steady-state gameplay it usually means you
are forgetting to return objects, or your peak concurrent usage is higher
than expected.

```dart
print('In pool: ${Particle.pool.length}');
print('Total created: ${Particle.pool.created}');
```


## Putting it together

A small example that emits and updates a fixed number of particles per frame,
returning expired ones to the pool:

```dart
class ParticleSystem extends Component {
    final List<Particle> _live = [];

    void emit(double x, double y) {
        final p = Particle.pool.get();
        p.x = x;
        p.y = y;
        p.life = 1.0;
        _live.add(p);
    }

    @override
    void update(double dt) {
        for (int i = _live.length - 1; i >= 0; i--) {
            final p = _live[i];
            p.life -= dt;
            if (p.life <= 0) {
                _live.removeAt(i);
                Particle.pool.add(p); // return to pool, reset() is called
            }
        }
    }
}
```

After the first burst the pool fills up, and subsequent emissions reuse those
particles instead of allocating new ones - exactly what we want from a hot
inner loop.
