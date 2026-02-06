import 'package:sizzle/sizzle.dart';

class Walkable {
  static const int none = 0;
  static const int leavingUp = 1;
  static const int leavingDown = 2;
  static const int leavingLeft = 4;
  static const int leavingRight = 8;
  static const int enteringUp = 16;
  static const int enteringDown = 32;
  static const int enteringLeft = 64;
  static const int enteringRight = 128;
}

class Joins {
  static const int none = 0;
  static const int up = 1;
  static const int down = 2;
  static const int left = 4;
  static const int right = 8;
  static const int upLeft = 16;
  static const int upRight = 32;
  static const int downLeft = 64;
  static const int downRight = 128;
}

class TileService extends ImageService {
  final List<Tile> tiles = [];
  final int tileWidth;
  final int tileHeight;

  TileService(
    super.assetFolder,
    this.tileWidth,
    this.tileHeight, {
    super.assetBundle,
    super.defaultProperties,
  });

  Tile getTile(int joins) {
    return tiles.firstWhere((tile) => tile.joins == joins);
  }

  @override
  Future<Image> load({
    ImageProperties? properties,
    String? path,
    bool cache = true,
  }) async {
    final image = await super.load(
      properties: properties,
      path: path,
      cache: cache,
    );
    // Cut the image into tiles
    String assetName = path ?? properties!.name;
    String tileName;
    for (int y = 0; y < image.height; y += tileHeight) {
      for (int x = 0; x < image.width; x += tileWidth) {
        tileName = '$assetName-$x-$y';
        final tileImage = await processImage(
            image,
            ImageProperties(
              '',
              crop: Rect.fromLTWH(
                x.toDouble(),
                y.toDouble(),
                tileWidth.toDouble(),
                tileHeight.toDouble(),
              ),
              ignoreDefaultProperties: true,
            ));
        int tileJoins = await calculateJoins(tileImage);
        if (tileJoins >= 0) {
          tiles.add(Tile(tileName, tileImage, tileJoins));
        }
      }
    }
    return image;
  }

  Future<int> calculateJoins(Image image) async {
    int joins = Joins.none;
    int xx = image.width - 1;
    int xc = xx >> 1;
    int yy = image.height - 1;
    int yc = yy >> 1;
    final pixels = await image.pixelsInUint8();
    if (pixels[0] == 0) {
      joins |= Joins.upLeft;
    }
    if (pixels[xx] == 0) {
      joins |= Joins.upRight;
    }
    if (pixels[yy * image.width] == 0) {
      joins |= Joins.downLeft;
    }
    if (pixels[xx + yy * image.width] == 0) {
      joins |= Joins.downRight;
    }
    if (pixels[xc] == 0) {
      joins |= Joins.up;
    }
    if (pixels[xc + yy * image.width] == 0) {
      joins |= Joins.down;
    }
    if (pixels[0 + yc * image.width] == 0) {
      joins |= Joins.left;
    }
    if (pixels[xx + yc * image.width] == 0) {
      joins |= Joins.right;
    }
    // Check if tile is empty
    if (joins == Joins.none) {
      // TODO: Change to checking every pixel?
      if (pixels[xc + yc * image.width] == 0) {
        return -1;
      }
    }
    return joins;
  }
}

class Tile {
  String name;
  final Image image;
  final int joins;

  Tile(this.name, this.image, this.joins);
}
