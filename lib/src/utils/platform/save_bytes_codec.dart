/// Encoding for storage backends that can only hold strings.
///
/// `localStorage` has no binary type, so binary save data has to be base64
/// encoded to live there. That alone is not enough: base64 is just text, so a
/// text entry read back through `readSaveBytes` would be handed to
/// [base64Decode] as if it were binary. Most strings fail that decode, but one
/// whose length happens to be a multiple of four decodes to garbage without an
/// error - a silent wrong answer, which is worse than a throw.
///
/// [saveBytesMarker] is therefore prepended to every binary entry, so the two
/// cases can be told apart. The result is that string-only storage behaves
/// exactly like the native file system in both directions:
///
/// | Written as | Read as | Result |
/// | --- | --- | --- |
/// | text | text | the text |
/// | text | bytes | the UTF-8 bytes of the text |
/// | bytes | bytes | the bytes |
/// | bytes | text | `FormatException` |
///
/// The last row matches `File.readAsString`, which throws `FormatException` on
/// bytes that are not valid UTF-8.
///
/// This library is plain Dart - no `dart:io`, no `package:web` - so both
/// `platform_web.dart` and `MemorySaveStorage` share it. `platform_io.dart`
/// does not need it, because a file holds real bytes.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Marks a stored string as base64 encoded binary rather than text.
///
/// Starts with NUL, which cannot appear in a Sizzle save document (JSON escapes
/// it) and is vanishingly unlikely in any other text a game stores. It is
/// written as an escape rather than a literal so this source file stays ASCII.
const String saveBytesMarker = '\u0000b64:';

/// Encode [bytes] as a string that [decodeSaveBytes] can recover exactly and
/// [decodeSaveText] will reject.
String encodeSaveBytes(Uint8List bytes) =>
    '$saveBytesMarker${base64Encode(bytes)}';

/// Recover the bytes from [stored].
///
/// A string written by [encodeSaveBytes] decodes back to the original bytes.
/// Anything else is text, and returns its UTF-8 bytes - which is what reading a
/// text file as bytes does on native platforms.
Uint8List decodeSaveBytes(String stored) {
  if (!stored.startsWith(saveBytesMarker)) {
    return utf8.encode(stored);
  }
  return base64Decode(stored.substring(saveBytesMarker.length));
}

/// Recover the text from [stored].
///
/// Throws a `FormatException` if [stored] holds binary data, matching
/// `File.readAsString` on a file that is not valid UTF-8. Reading binary data
/// as text is a mistake worth reporting rather than papering over.
String decodeSaveText(String stored) {
  if (stored.startsWith(saveBytesMarker)) {
    throw const FormatException(
      'the stored data is binary and cannot be read as text',
    );
  }
  return stored;
}
