import 'dart:math';

import 'package:flame/extensions.dart';
import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

/// Parsed lit-SVG data.
///
/// Parses a small subset of SVG into in-memory data structures suitable for
/// later rendering by `LitSvgComponent`. The supported subset is intentionally
/// narrow:
///
/// * The root `<svg>` element must declare the Paraplu namespace
///   (`xmlns:pp="http://paraplu.io/svg"`) and supplies `width`, `height`, and
///   the custom `pp:origin="x y"` attribute (the SVG's local origin in
///   viewBox pixels — typically what a `PositionComponent` anchor will be
///   derived from).
/// * `<defs>` may contain `<g id="...">` group definitions. Each group may
///   carry the custom `pp:material` attribute and may contain `<path>` nodes.
/// * Top-level `<use xlink:href="#id" transform="..."/>` references build the
///   render list. All standard SVG transform functions are supported.
/// * Path `d` data supports the line/move/close commands only:
///   `M m L l H h V v Z z` (curves and arcs are not yet supported).
class LitSvgData {
  /// The Paraplu namespace URI that must be declared on the root `<svg>`
  /// element via `xmlns:pp="..."`. Without this, [LitSvgData] refuses to parse.
  static const String paraplu = 'http://paraplu.io/svg';

  final Vector2 size = Vector2.zero();
  final Vector2 origin = Vector2.zero();
  final List<LitSvgGroup> groups = <LitSvgGroup>[];
  final List<LitSvgRenderItem> renderList = <LitSvgRenderItem>[];

  LitSvgData(String data) {
    final doc = XmlDocument.parse(data);
    final root = doc.rootElement;
    if (root.name.local != 'svg') {
      throw FormatException(
        'Root element must be <svg>, got <${root.name.local}>',
      );
    }
    if (root.getAttribute('xmlns:pp') != paraplu) {
      throw FormatException(
        'SVG must declare xmlns:pp="$paraplu" on the root <svg> element',
      );
    }
    _parseRoot(root);
  }

  void _parseRoot(XmlElement root) {
    final w = root.getAttribute('width');
    final h = root.getAttribute('height');
    if (w != null) size.x = double.parse(w);
    if (h != null) size.y = double.parse(h);

    final originStr = root.getAttribute('pp:origin');
    if (originStr != null) {
      final parts = originStr.trim().split(RegExp(r'[\s,]+'));
      if (parts.length < 2) {
        throw FormatException('pp:origin needs two numbers, got "$originStr"');
      }
      origin.x = double.parse(parts[0]);
      origin.y = double.parse(parts[1]);
    }

    final groupsById = <String, LitSvgGroup>{};
    for (final defs in root.findElements('defs')) {
      for (final g in defs.findElements('g')) {
        final group = _parseGroup(g);
        groups.add(group);
        if (group.id.isNotEmpty) {
          groupsById[group.id] = group;
        }
      }
    }

    for (final use in root.findElements('use')) {
      final href = use.getAttribute('xlink:href') ?? use.getAttribute('href');
      if (href == null || !href.startsWith('#')) {
        throw FormatException('use element missing valid href');
      }
      final id = href.substring(1);
      final group = groupsById[id];
      if (group == null) {
        throw FormatException('use references unknown group: $id');
      }
      final transform = parseTransform(use.getAttribute('transform'));
      renderList.add(LitSvgRenderItem(group, transform));
    }
  }

  LitSvgGroup _parseGroup(XmlElement g) {
    final group = LitSvgGroup();
    group.id = g.getAttribute('id') ?? '';
    group.expand = _parseExpand(g.getAttribute('pp:expand'));

    final matStr = g.getAttribute('pp:material');
    if (matStr != null) {
      final parsed = parseMaterial(matStr);
      group.material.baseColor = parsed.baseColor;
      group.material.topColor = parsed.topColor;
      group.material.sheen = parsed.sheen;
    }

    for (final p in g.findElements('path')) {
      final d = p.getAttribute('d');
      if (d == null) continue;

      Vector3 normal = Vector3.zero();
      final fill = p.getAttribute('fill');
      if (fill != null) {
        normal = normalFromColor(parseColor(fill));
      }

      final pathExpand = _parseExpand(p.getAttribute('pp:expand'));
      final totalExpand = group.expand + pathExpand;

      for (final verts in _PathParser(d).parse()) {
        final out =
            totalExpand == 0 ? verts : _expandPolygon(verts, totalExpand);
        final svgPath = LitSvgPath()
          ..normal = normal.clone()
          ..expand = pathExpand;
        _writeVertices(svgPath.uiPath, out);
        group.paths.add(svgPath);
      }
    }

    return group;
  }

  static double _parseExpand(String? s) {
    if (s == null) return 0;
    return double.parse(s.trim());
  }

  static void _writeVertices(Path path, List<Vector2> verts) {
    if (verts.isEmpty) return;
    path.moveTo(verts[0].x, verts[0].y);
    for (var i = 1; i < verts.length; i++) {
      path.lineTo(verts[i].x, verts[i].y);
    }
    path.close();
  }

  /// Offset each edge of a closed polygon outward (positive [amount]) or
  /// inward (negative) by [amount] pixels along its perpendicular. New
  /// vertices are computed as the intersection of adjacent shifted edges.
  /// Exposed for testing.
  @visibleForTesting
  static List<Vector2> expandPolygon(List<Vector2> verts, double amount) =>
      _expandPolygon(verts, amount);

  static List<Vector2> _expandPolygon(List<Vector2> verts, double amount) {
    final n = verts.length;
    if (n < 3 || amount == 0) return verts;

    // Signed area determines winding (in Y-down screen coords, positive
    // signed area corresponds to clockwise winding).
    double signedArea = 0;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      signedArea += (verts[j].x - verts[i].x) * (verts[j].y + verts[i].y);
    }
    final cw = signedArea > 0;

    // Outward unit normal per edge.
    final normals = List<Vector2>.generate(n, (i) {
      final j = (i + 1) % n;
      final dx = verts[j].x - verts[i].x;
      final dy = verts[j].y - verts[i].y;
      final len = sqrt(dx * dx + dy * dy);
      if (len < 1e-9) return Vector2.zero();
      return cw ? Vector2(-dy / len, dx / len) : Vector2(dy / len, -dx / len);
    });

    return List<Vector2>.generate(n, (i) {
      final prev = (i - 1 + n) % n;
      final n1 = normals[prev];
      final n2 = normals[i];
      final p1 = Vector2(
        verts[prev].x + amount * n1.x,
        verts[prev].y + amount * n1.y,
      );
      final p2 = Vector2(
        verts[i].x + amount * n1.x,
        verts[i].y + amount * n1.y,
      );
      final p3 = Vector2(
        verts[i].x + amount * n2.x,
        verts[i].y + amount * n2.y,
      );
      final p4 = Vector2(
        verts[(i + 1) % n].x + amount * n2.x,
        verts[(i + 1) % n].y + amount * n2.y,
      );
      return _lineIntersect(p1, p2, p3, p4) ?? p2;
    });
  }

  static Vector2? _lineIntersect(
    Vector2 p1,
    Vector2 p2,
    Vector2 p3,
    Vector2 p4,
  ) {
    final denom = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x);
    if (denom.abs() < 1e-9) return null;
    final t =
        ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / denom;
    return Vector2(p1.x + t * (p2.x - p1.x), p1.y + t * (p2.y - p1.y));
  }

  /// Parse a `#RGB`, `#RRGGBB`, or `#AARRGGBB` color literal.
  /// `#RGB` expands each digit (e.g. `#abc` → `#aabbcc`) and is fully opaque.
  @visibleForTesting
  static Color parseColor(String hex) {
    if (!hex.startsWith('#')) {
      throw FormatException('Color must start with #: "$hex"');
    }
    final h = hex.substring(1);
    if (h.length == 3) {
      final r = h[0];
      final g = h[1];
      final b = h[2];
      return Color(0xFF000000 | int.parse('$r$r$g$g$b$b', radix: 16));
    }
    if (h.length == 6) {
      return Color(0xFF000000 | int.parse(h, radix: 16));
    }
    if (h.length == 8) {
      return Color(int.parse(h, radix: 16));
    }
    throw FormatException(
      'Color must be #RGB, #RRGGBB or #AARRGGBB: "$hex"',
    );
  }

  /// Parse a `pp:material` attribute value.
  ///
  /// Accepts 1, 2, or 3 whitespace-separated tokens:
  /// * `"#color"` — base = top = color, sheen = matte
  /// * `"#color sheen"` — base = top = color, sheen = parsed
  /// * `"#base #top sheen"` — base, top, sheen
  @visibleForTesting
  static LitSvgMaterial parseMaterial(String s) {
    final tokens = s.trim().split(RegExp(r'\s+'));
    final mat = LitSvgMaterial();
    switch (tokens.length) {
      case 1:
        mat.baseColor = parseColor(tokens[0]);
        mat.topColor = mat.baseColor;
        mat.sheen = LitSvgMaterialSheen.matte;
        break;
      case 2:
        mat.baseColor = parseColor(tokens[0]);
        mat.topColor = mat.baseColor;
        mat.sheen = _parseSheen(tokens[1]);
        break;
      case 3:
        mat.baseColor = parseColor(tokens[0]);
        mat.topColor = parseColor(tokens[1]);
        mat.sheen = _parseSheen(tokens[2]);
        break;
      default:
        throw FormatException(
          'pp:material must have 1, 2, or 3 tokens, got ${tokens.length}',
        );
    }
    return mat;
  }

  static LitSvgMaterialSheen _parseSheen(String s) {
    switch (s) {
      case 'd':
      case 'dull':
        return LitSvgMaterialSheen.dull;
      case 'm':
      case 'matte':
        return LitSvgMaterialSheen.matte;
      case 'g':
      case 'gloss':
        return LitSvgMaterialSheen.gloss;
      case 's':
      case 'specular':
        return LitSvgMaterialSheen.specular;
      default:
        throw FormatException('Unknown sheen: "$s"');
    }
  }

  /// Decode a fill color into a unit normal vector using standard normal-map
  /// encoding: each channel maps `[0, 255]` to `[-1, 1]`. Result is normalized.
  @visibleForTesting

  /// Decode a Paraplu normal-map fill colour into a unit normal.
  ///
  /// Standard normal-map encoding maps each colour channel `[0, 255]` to
  /// `[-1, 1]`. The G channel encodes "tangent-up" — meaning a high G
  /// value (e.g. `#80ff80`) represents a surface facing **screen-up**.
  /// Because Sizzle's render canvas uses Y-down coordinates, that
  /// convention flips: tangent-up (`G high`) → screen-up = `-Y`. The
  /// decoder negates the green channel so a `#80ff80` fill produces a
  /// normal pointing in the `-Y` direction (screen-up).
  static Vector3 normalFromColor(Color c) {
    final argb = c.toARGB32();
    final r = ((argb >> 16) & 0xFF) / 255.0 * 2.0 - 1.0;
    final g = ((argb >> 8) & 0xFF) / 255.0 * 2.0 - 1.0;
    final b = (argb & 0xFF) / 255.0 * 2.0 - 1.0;
    final v = Vector3(r, -g, b);
    if (v.length2 > 0) v.normalize();
    return v;
  }

  /// Parse an SVG `transform` attribute into a [Matrix4]. Returns identity if
  /// [data] is null or empty. Supports `translate`, `scale`, `rotate`,
  /// `skewX`, `skewY`, and `matrix`. Multiple functions compose left-to-right.
  @visibleForTesting
  static Matrix4 parseTransform(String? data) {
    if (data == null || data.trim().isEmpty) return Matrix4.identity();
    final result = Matrix4.identity();
    final regex = RegExp(r'(\w+)\s*\(([^)]*)\)');
    bool any = false;
    for (final m in regex.allMatches(data)) {
      any = true;
      final name = m.group(1)!;
      final args = _parseNumberList(m.group(2)!);
      result.multiply(_buildTransform(name, args));
    }
    if (!any) {
      throw FormatException('Could not parse transform: "$data"');
    }
    return result;
  }

  static Matrix4 _buildTransform(String name, List<double> args) {
    switch (name) {
      case 'translate':
        if (args.isEmpty) {
          throw FormatException('translate requires at least 1 argument');
        }
        final tx = args[0];
        final ty = args.length > 1 ? args[1] : 0.0;
        return Matrix4.translationValues(tx, ty, 0);
      case 'scale':
        if (args.isEmpty) {
          throw FormatException('scale requires at least 1 argument');
        }
        final sx = args[0];
        final sy = args.length > 1 ? args[1] : sx;
        return Matrix4.diagonal3Values(sx, sy, 1);
      case 'rotate':
        if (args.isEmpty) {
          throw FormatException('rotate requires at least 1 argument');
        }
        final a = args[0] * pi / 180.0;
        if (args.length >= 3) {
          final cx = args[1];
          final cy = args[2];
          final m = Matrix4.identity()..translateByDouble(cx, cy, 0, 1);
          m.rotateZ(a);
          m.translateByDouble(-cx, -cy, 0, 1);
          return m;
        }
        return Matrix4.rotationZ(a);
      case 'skewX':
        if (args.isEmpty) {
          throw FormatException('skewX requires 1 argument');
        }
        final t = tan(args[0] * pi / 180.0);
        return Matrix4.identity()..setEntry(0, 1, t);
      case 'skewY':
        if (args.isEmpty) {
          throw FormatException('skewY requires 1 argument');
        }
        final t = tan(args[0] * pi / 180.0);
        return Matrix4.identity()..setEntry(1, 0, t);
      case 'matrix':
        if (args.length != 6) {
          throw FormatException(
              'matrix requires 6 arguments, got ${args.length}');
        }
        final a = args[0],
            b = args[1],
            c = args[2],
            d = args[3],
            e = args[4],
            f = args[5];
        return Matrix4.identity()
          ..setColumn(0, Vector4(a, b, 0, 0))
          ..setColumn(1, Vector4(c, d, 0, 0))
          ..setColumn(3, Vector4(e, f, 0, 1));
      default:
        throw FormatException('Unknown transform: "$name"');
    }
  }

  static List<double> _parseNumberList(String s) {
    final reader = _NumberReader(s);
    final out = <double>[];
    while (reader.hasMore) {
      out.add(reader.readNumber());
    }
    return out;
  }
}

/// An item on the render list
class LitSvgRenderItem {
  final LitSvgGroup group;
  final Matrix4 transform;
  LitSvgRenderItem(this.group, this.transform);
}

/// A group definition
class LitSvgGroup {
  String id = '';
  final LitSvgMaterial material = LitSvgMaterial();
  final List<LitSvgPath> paths = <LitSvgPath>[];

  /// Optional `pp:expand` value on the group, in viewBox pixels. Each path
  /// in the group is offset outward (positive) or inward (negative) by this
  /// many pixels per edge. Stacks additively with [LitSvgPath.expand].
  double expand = 0;
}

/// A closed path baked as a `dart:ui` [Path]. Vertices are not retained
/// separately — the parser writes them directly into [uiPath] and (where
/// relevant) applies any `pp:expand` offset before doing so.
class LitSvgPath {
  Vector3 normal = Vector3.zero();

  /// The closed path in viewBox coordinates. Shared across every
  /// `LitSvgComponent` referencing the same parsed [LitSvgData].
  final Path uiPath = Path();

  /// Optional `pp:expand` value on the path, in viewBox pixels. Stacks
  /// additively with the parent group's [LitSvgGroup.expand].
  double expand = 0;
}

/// The material definition for a group, as defined in the pp:material attribute.
/// The attribute is either 1, 2 or 3 items separated by whitespace:
/// "baseColor" (topColor = baseColor, sheen = matte)
/// "baseColor sheen" (topColor = baseColor)
/// "baseColor topColor sheen"
/// The baseColor and topColor are 3, 6, or 8 digit hex:
/// #RGB (each digit doubled, alpha is assumed to be 255)
/// #RRGGBB (alpha is assumed to be 255)
/// #AARRGGBB
/// Sheen may be `dull`, `matte`, `gloss`, `specular`, or just the first letter
/// (`d`, `m`, `g`, `s`).
class LitSvgMaterial {
  LitSvgMaterialSheen sheen = LitSvgMaterialSheen.matte;
  Color baseColor = const Color(0xFF000000);
  Color topColor = const Color(0xFF000000);
}

/// The sheen levels.
/// matte is default
enum LitSvgMaterialSheen { dull, matte, gloss, specular }

/// Parses the subset of SVG path commands documented on [LitSvgData]:
/// `M m L l H h V v Z z`, plus implicit continuation per the SVG spec.
///
/// Returns one vertex list per subpath. Each `M`/`m` after the first (or
/// after a `Z`/`z`) starts a new subpath in the returned list. Closing is
/// implicit — `Z`/`z` resets the current point to the subpath start but
/// does not append a vertex.
class _PathParser {
  _PathParser(this._data);

  final String _data;
  int _pos = 0;
  String _lastCmd = '';
  Vector2 _current = Vector2.zero();
  Vector2 _start = Vector2.zero();
  final List<List<Vector2>> _paths = <List<Vector2>>[];
  List<Vector2>? _path;

  List<List<Vector2>> parse() {
    while (_pos < _data.length) {
      _skipSep();
      if (_pos >= _data.length) break;
      final c = _data[_pos];
      if (_isCommand(c)) {
        _pos++;
        _runCommand(c);
      } else if (_isNumberStart(c)) {
        final implicit = _implicitCommand();
        if (implicit == null) {
          throw FormatException(
            'Path data starts with a number without a command at $_pos',
          );
        }
        _runCommand(implicit);
      } else {
        throw FormatException(
          'Unexpected character "$c" in path data at $_pos',
        );
      }
    }
    _flush();
    return _paths;
  }

  String? _implicitCommand() {
    switch (_lastCmd) {
      case 'M':
        return 'L';
      case 'm':
        return 'l';
      case 'L':
      case 'l':
      case 'H':
      case 'h':
      case 'V':
      case 'v':
        return _lastCmd;
      default:
        return null;
    }
  }

  void _runCommand(String c) {
    _lastCmd = c;
    switch (c) {
      case 'M':
        _flush();
        _path = <Vector2>[];
        _current = Vector2(_readNumber(), _readNumber());
        _start = _current.clone();
        _path!.add(_current.clone());
        break;
      case 'm':
        _flush();
        _path = <Vector2>[];
        _current = _current + Vector2(_readNumber(), _readNumber());
        _start = _current.clone();
        _path!.add(_current.clone());
        break;
      case 'L':
        _current = Vector2(_readNumber(), _readNumber());
        _addVertex();
        break;
      case 'l':
        _current = _current + Vector2(_readNumber(), _readNumber());
        _addVertex();
        break;
      case 'H':
        _current = Vector2(_readNumber(), _current.y);
        _addVertex();
        break;
      case 'h':
        _current = Vector2(_current.x + _readNumber(), _current.y);
        _addVertex();
        break;
      case 'V':
        _current = Vector2(_current.x, _readNumber());
        _addVertex();
        break;
      case 'v':
        _current = Vector2(_current.x, _current.y + _readNumber());
        _addVertex();
        break;
      case 'Z':
      case 'z':
        _current = _start.clone();
        break;
      default:
        throw FormatException('Unsupported path command "$c"');
    }
  }

  void _addVertex() {
    (_path ??= <Vector2>[]).add(_current.clone());
  }

  void _flush() {
    final p = _path;
    if (p != null && p.isNotEmpty) {
      _paths.add(p);
    }
    _path = null;
  }

  bool _isCommand(String c) => 'MmLlHhVvZz'.contains(c);
  bool _isNumberStart(String c) => '0123456789.+-'.contains(c);

  void _skipSep() {
    while (_pos < _data.length) {
      final ch = _data.codeUnitAt(_pos);
      if (ch == 0x20 || ch == 0x09 || ch == 0x0a || ch == 0x0d || ch == 0x2c) {
        _pos++;
      } else {
        break;
      }
    }
  }

  double _readNumber() {
    _skipSep();
    if (_pos >= _data.length) {
      throw FormatException('Expected number at end of path data');
    }
    final start = _pos;
    if (_data[_pos] == '+' || _data[_pos] == '-') _pos++;
    bool sawDigit = false;
    bool sawDot = false;
    while (_pos < _data.length) {
      final ch = _data.codeUnitAt(_pos);
      if (ch >= 0x30 && ch <= 0x39) {
        sawDigit = true;
        _pos++;
      } else if (ch == 0x2e && !sawDot) {
        sawDot = true;
        _pos++;
      } else {
        break;
      }
    }
    if (_pos < _data.length) {
      final ch = _data.codeUnitAt(_pos);
      if (ch == 0x65 || ch == 0x45) {
        _pos++;
        if (_pos < _data.length && (_data[_pos] == '+' || _data[_pos] == '-')) {
          _pos++;
        }
        while (_pos < _data.length) {
          final c2 = _data.codeUnitAt(_pos);
          if (c2 >= 0x30 && c2 <= 0x39) {
            _pos++;
          } else {
            break;
          }
        }
      }
    }
    if (!sawDigit) {
      throw FormatException('Invalid number in path data at $start');
    }
    return double.parse(_data.substring(start, _pos));
  }
}

/// Reads numbers out of an SVG transform argument list (whitespace and/or
/// comma separated). Shares its number grammar with [_PathParser].
class _NumberReader {
  _NumberReader(this._data);

  final String _data;
  int _pos = 0;

  bool get hasMore {
    _skipSep();
    return _pos < _data.length;
  }

  double readNumber() {
    _skipSep();
    if (_pos >= _data.length) {
      throw FormatException('Expected number at end of input');
    }
    final start = _pos;
    if (_data[_pos] == '+' || _data[_pos] == '-') _pos++;
    bool sawDigit = false;
    bool sawDot = false;
    while (_pos < _data.length) {
      final ch = _data.codeUnitAt(_pos);
      if (ch >= 0x30 && ch <= 0x39) {
        sawDigit = true;
        _pos++;
      } else if (ch == 0x2e && !sawDot) {
        sawDot = true;
        _pos++;
      } else {
        break;
      }
    }
    if (_pos < _data.length) {
      final ch = _data.codeUnitAt(_pos);
      if (ch == 0x65 || ch == 0x45) {
        _pos++;
        if (_pos < _data.length && (_data[_pos] == '+' || _data[_pos] == '-')) {
          _pos++;
        }
        while (_pos < _data.length) {
          final c2 = _data.codeUnitAt(_pos);
          if (c2 >= 0x30 && c2 <= 0x39) {
            _pos++;
          } else {
            break;
          }
        }
      }
    }
    if (!sawDigit) {
      throw FormatException('Invalid number at $start');
    }
    return double.parse(_data.substring(start, _pos));
  }

  void _skipSep() {
    while (_pos < _data.length) {
      final ch = _data.codeUnitAt(_pos);
      if (ch == 0x20 || ch == 0x09 || ch == 0x0a || ch == 0x0d || ch == 0x2c) {
        _pos++;
      } else {
        break;
      }
    }
  }
}
