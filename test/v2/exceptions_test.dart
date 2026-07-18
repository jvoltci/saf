import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/exceptions.dart';

void main() {
  PlatformException pe(String code) => PlatformException(
      code: code, message: 'boom', details: {'uri': 'content://x'});

  test('maps stable codes to typed exceptions', () {
    expect(
        mapPlatformException(pe('permission')), isA<SafPermissionException>());
    expect(mapPlatformException(pe('not_found')), isA<SafNotFoundException>());
    expect(mapPlatformException(pe('already_exists')),
        isA<SafAlreadyExistsException>());
    expect(mapPlatformException(pe('io')), isA<SafIoException>());
  });

  test('unknown codes map to SafIoException', () {
    expect(mapPlatformException(pe('weird_code')), isA<SafIoException>());
  });

  test('carries uri and message', () {
    final e = mapPlatformException(pe('not_found'));
    expect(e.uri, 'content://x');
    expect(e.message, 'boom');
    expect(e.toString(), contains('content://x'));
  });

  test('tolerates missing details', () {
    final e = mapPlatformException(
        PlatformException(code: 'io', message: null, details: null));
    expect(e.uri, '');
    expect(e.message, 'io');
  });
}
