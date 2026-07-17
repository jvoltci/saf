import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/storage_access_framework/api.dart';

void main() {
  group('makeDirectoryPath', () {
    test('decodes a primary-volume tree URI', () {
      final uri =
          'content://com.android.externalstorage.documents/tree/primary%3AMyApp';
      expect(makeDirectoryPath(uri), 'MyApp');
    });

    test('decodes a nested primary-volume path', () {
      final uri =
          'content://com.android.externalstorage.documents/tree/primary%3AAndroid%2Fmedia%2Fmatrix';
      expect(makeDirectoryPath(uri), 'Android/media/matrix');
    });

    // Regression for #41: external/removable volumes have a volume id
    // instead of `primary`, which used to throw `RangeError`.
    test('decodes an external (SD/USB) volume URI without throwing', () {
      final uri =
          'content://com.android.externalstorage.documents/tree/ABB8-7BD7%3APRIVATE%2FSONY';
      expect(makeDirectoryPath(uri), 'PRIVATE/SONY');
    });

    test('handles an external volume URI with an empty path', () {
      final uri =
          'content://com.android.externalstorage.documents/tree/00D0-08B0%3A';
      expect(makeDirectoryPath(uri), '');
    });

    test('returns the decoded input when no volume marker is present', () {
      expect(makeDirectoryPath('MyApp'), 'MyApp');
    });
  });

  group('normalizeDirectoryPath', () {
    test('strips the primary external-storage root', () {
      expect(normalizeDirectoryPath('/storage/emulated/0/MyApp'), 'MyApp');
    });

    test('strips the sdcard root and surrounding slashes', () {
      expect(normalizeDirectoryPath('/sdcard/MyApp/'), 'MyApp');
    });

    test('leaves an already-relative path untouched', () {
      expect(normalizeDirectoryPath('MyApp'), 'MyApp');
    });
  });

  group('isSameDirectoryPath', () {
    test('matches a filesystem path against its SAF-relative form', () {
      expect(isSameDirectoryPath('/storage/emulated/0/MyApp', 'MyApp'), isTrue);
    });

    test('matches identical relative paths', () {
      expect(isSameDirectoryPath('Android/media', 'Android/media'), isTrue);
    });

    test('does not match different directories', () {
      expect(isSameDirectoryPath('MyApp', 'OtherApp'), isFalse);
    });

    test('does not match on a partial segment', () {
      expect(isSameDirectoryPath('App', 'MyApp'), isFalse);
    });
  });
}
