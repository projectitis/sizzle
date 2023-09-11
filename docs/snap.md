# Snap

[:arrow_left: Back to documentation](index.md)

`Snap` is a mixin that is applied to sprites and other game objects. It ensures your game objects
scale automatically to the right size, and (optionally) that they snap to the nearest scaled pixel.

To use snap, just mix it with a `PositionComponent` such as a SpriteComponent.

```dart
class PixelSprite extends SpriteComponent with Snap {
    // Code omitted.
}
```


## Snap should not be nested

Components with `Snap` should never be nested inside each other. i.e. a component with `Snap` should
never be a child (or a descendant) of another component with `Snap`. Scaling will be applied
multiple times, and your object will be huge!

Only your base component should have `Snap` and all child components should be unscaled.


## Components with snap

Sizzle provides a number of Flame components that already have snap applied. If none of these suit
your needs you can always make your own.

- `SnapPositionComponent`
- `SnapSpriteComponent`
- `SnapRectangleComponent`


## Scaling to the correct size

A `Snap` component will always scale to the correct target size for your game (see
[screen size]). You can turn this off by setting `useSnapScale` to `false`.

```dart
spriteWithSnap.useSnapScale = false;
```


## Snapping to the nearest whole pixel

Many modern (non-traditional) pixel art games use large pixels but combine that with smooth
movement. Traditional pixel art games stay on whole pixels (i.e. snap to pixels).

A `Snap` component will snap tp the nearest whole pixel as it moves. If this is not the artistic
style you are going for, you can turn this off by setting `useSnap` to `false`.

```dart
spriteWithSnap.useSnap = false;
```


## Positioning

A component with snap is anchored to the `maxWindow` by default. To change this, set
`anchorWindow` to any of the `AnchorWindow` enums:

- `AnchorWindow.maxWindow`
- `AnchorWindow.viewWindow`
- `AnchorWindow.targetWindow`

See [screen size] for a description of these windows.

```dart
spriteWithSnap.anchorWindow = AnchorWindow.targetWindow;
```

[screen size]: game_structure.md#screen-size
