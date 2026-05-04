# Sizzle Engine — Incoming Requirements

Requirements from game projects that should be implemented in the engine. Each entry is added by the game project's agent and will be picked up by the Sizzle development agent.

---

## Event Coordinate Transformation for Letterbox Offset
- **Requested by**: All In: Dead River
- **Description**: SizzleGame.renderTree applies a canvas translation (`viewWindow.left - gameWindow.left`, `viewWindow.top - gameWindow.top`) for letterboxing, but Flame's event system (TapCallbacks, DragCallbacks) does not account for this offset. Events arrive in screen coordinates while components are positioned in game coordinates, causing all hit testing to miss when the window size differs from the target size.
- **Use case**: Any interactive component (buttons, lists, tap targets) fails to receive events on desktop where the window is larger than the target size. On a watch this may be less noticeable since the display matches the target, but it breaks desktop testing entirely.
- **Priority**: high
- **Status**: pending
- **Notes**: The fix should transform event coordinates through the same offset applied in renderTree. Options include: (1) override `componentsAtPoint` to adjust the point before hit testing, (2) use Flame's camera/viewport system instead of manual canvas translation, or (3) override event dispatch methods to transform coordinates. Game currently works around this by overriding `containsLocalPoint` and adjusting event positions on individual components, which is fragile and must be repeated for every interactive component.

<!-- Add new requirements above this line using the template below:

## [Feature Name]
- **Requested by**: [Game project name]
- **Description**: [What the feature should do]
- **Use case**: [How the game needs to use it]
- **Priority**: [high/medium/low]
- **Status**: pending
- **Notes**: [Any implementation hints or constraints]

-->
