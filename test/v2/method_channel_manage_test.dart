// test/v2/method_channel_manage_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/exceptions.dart';
import 'package:saf/src/v2/models.dart';
import 'package:saf/src/v2/saf_method_channel.dart';

const docMap = {
  'uri': 'content://doc/1',
  'name': 'a.txt',
  'isDir': false,
  'length': 3,
  'lastModified': 2,
  'mimeType': 'text/plain',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = MethodChannelSaf();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  MethodCall? lastCall;
  void mock(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      lastCall = call;
      return handler(call);
    });
  }

  tearDown(() =>
      messenger.setMockMethodCallHandler(platform.methodChannel, null));

  test('list decodes children', () async {
    mock((_) => [docMap]);
    final kids = await platform.list('content://dir');
    expect(lastCall!.arguments, {'dirUri': 'content://dir'});
    expect(kids.single.name, 'a.txt');
  });

  test('stat returns null for missing; exists mirrors stat', () async {
    mock((_) => null);
    expect(await platform.stat('u'), isNull);
    expect(await platform.exists('u'), isFalse);
    mock((_) => docMap);
    expect(await platform.exists('u'), isTrue);
  });

  test('child passes multi-segment names', () async {
    mock((_) => docMap);
    await platform.child('content://dir', ['a', 'b']);
    expect(lastCall!.arguments, {
      'dirUri': 'content://dir',
      'names': ['a', 'b']
    });
  });

  test('mkdirp returns created dir', () async {
    mock((_) => {...docMap, 'isDir': true});
    final d = await platform.mkdirp('content://dir', ['x']);
    expect(d.isDir, isTrue);
  });

  test('delete sends uri', () async {
    mock((_) => null);
    await platform.delete('content://doc/1');
    expect(lastCall!.method, 'delete');
  });

  test('rename returns renamed doc', () async {
    mock((_) => {...docMap, 'name': 'b.txt'});
    final d = await platform.rename('content://doc/1', 'b.txt');
    expect(lastCall!.arguments, {'uri': 'content://doc/1', 'newName': 'b.txt'});
    expect(d.name, 'b.txt');
  });

  test('PlatformException becomes typed SafException', () async {
    mock((_) => throw PlatformException(
        code: 'not_found', message: 'gone', details: {'uri': 'u'}));
    expect(() => platform.list('u'), throwsA(isA<SafNotFoundException>()));
  });
}
