/// Library for making bitmap games using flame
library sizzle;

/// External exports
export 'package:flutter/widgets.dart' show runApp;
export 'package:flame/cache.dart';
export 'package:flame/collisions.dart';
export 'package:flame/components.dart';
export 'package:flame/effects.dart';
export 'package:flame/extensions.dart';
export 'package:flame/flame.dart';
export 'package:flame/game.dart';
export 'package:flame/sprite.dart';
export 'package:flame/text.dart';
export 'package:flame/timer.dart';
export 'package:flame/events.dart';

/// Sizzle exports
export 'src/game/game.dart';
export 'src/game/scene.dart';
export 'src/display/dialog.dart';
export 'src/display/environment.dart';
export 'src/display/lightning.dart';
export 'src/display/snap.dart';
export 'src/display/shape.dart';
export 'src/display/sprite.dart';
export 'src/display/lit_svg_data.dart';
export 'src/display/lit_svg_component.dart';
export 'src/display/svg_image.dart';
export 'src/display/tile.dart';
export 'src/display/ninegrid.dart';
export 'src/math/easing.dart';
export 'src/math/math.dart';
export 'src/math/vector_math.dart';
export 'src/physics/lifetime.dart';
export 'src/physics/movement.dart';
export 'src/text/text.dart';
export 'src/utils/bitset.dart';
export 'src/utils/config.dart';
export 'src/utils/device.dart';
export 'src/utils/logger.dart';
export 'src/utils/pool.dart';
export 'src/utils/services.dart';
export 'src/utils/services/dialog_service.dart';
export 'src/utils/services/file_service.dart';
export 'src/utils/services/flag_service.dart';
export 'src/utils/services/image_service.dart';
export 'src/utils/services/lit_svg_service.dart';
export 'src/utils/services/tween_service.dart';
