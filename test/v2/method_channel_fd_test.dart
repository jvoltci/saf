// test/v2/method_channel_fd_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/exceptions.dart';
import 'package:saf/src/v2/saf_method_channel.dart';

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

  tearDown(
      () => messenger.setMockMethodCallHandler(platform.methodChannel, null));

  test('openFileDescriptor forwards args and decodes SafOpenFd', () async {
    mock((_) => {'fd': 42, 'path': '/proc/self/fd/42'});
    final d = await platform.openFileDescriptor('content://doc/1', 'rw');
    expect(lastCall!.method, 'openFileDescriptor');
    expect(lastCall!.arguments, {'uri': 'content://doc/1', 'mode': 'rw'});
    expect(d.fd, 42);
    expect(d.path, '/proc/self/fd/42');
  });

  test('closeFileDescriptor sends fd', () async {
    mock((_) => null);
    await platform.closeFileDescriptor(42);
    expect(lastCall!.method, 'closeFileDescriptor');
    expect(lastCall!.arguments, {'fd': 42});
  });

  test('thumbnail forwards args and returns bytes', () async {
    mock((_) => Uint8List.fromList([1, 2, 3]));
    final b = await platform.thumbnail('content://doc/1', 128, 96, 80);
    expect(lastCall!.method, 'thumbnail');
    expect(lastCall!.arguments,
        {'uri': 'content://doc/1', 'width': 128, 'height': 96, 'quality': 80});
    expect(b, [1, 2, 3]);
  });

  test('thumbnail returns null when provider has none', () async {
    mock((_) => null);
    expect(await platform.thumbnail('u', 64, 64, 50), isNull);
  });

  test('openFileDescriptor maps PlatformException to typed SafException',
      () async {
    mock((_) => throw PlatformException(
        code: 'not_found', message: 'gone', details: {'uri': 'u'}));
    expect(() => platform.openFileDescriptor('u', 'r'),
        throwsA(isA<SafNotFoundException>()));
  });
}
