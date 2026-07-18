// test/v2/method_channel_progress_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/models.dart';
import 'package:saf/src/v2/saf_method_channel.dart';

const docMap = {
  'uri': 'content://doc/copied',
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

  tearDown(
      () => messenger.setMockMethodCallHandler(platform.methodChannel, null));

  test('copyTo without progress is a plain call', () async {
    late MethodCall seen;
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      seen = call;
      return docMap;
    });
    final d = await platform.copyTo('content://src', 'content://dest');
    expect(seen.method, 'copyTo');
    expect(seen.arguments['withProgress'], false);
    expect(d, SafDocumentFile.fromMap(docMap));
  });

  test('copyTo with progress consumes the event session', () async {
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      expect(call.arguments['withProgress'], true);
      return 's1';
    });
    messenger.setMockStreamHandler(
      EventChannel('${MethodChannelSaf.eventsPrefix}s1'),
      MockStreamHandler.inline(onListen: (args, events) {
        events.success({
          'type': 'progress',
          'bytesDone': 5,
          'totalBytes': 10,
          'currentName': 'a.txt'
        });
        events.success({'type': 'done', 'file': docMap});
        events.endOfStream();
      }),
    );
    final seen = <SafProgress>[];
    final d = await platform.copyTo('content://src', 'content://dest',
        onProgress: seen.add);
    expect(seen.single.bytesDone, 5);
    expect(seen.single.totalBytes, 10);
    expect(d.uri, 'content://doc/copied');
  });

  test('copyToLocalFile with progress completes on done with null file',
      () async {
    messenger.setMockMethodCallHandler(
        platform.methodChannel, (call) async => 's2');
    messenger.setMockStreamHandler(
      EventChannel('${MethodChannelSaf.eventsPrefix}s2'),
      MockStreamHandler.inline(onListen: (args, events) {
        events.success({'type': 'done', 'file': null});
        events.endOfStream();
      }),
    );
    await platform.copyToLocalFile('content://src', '/tmp/x',
        onProgress: (_) {});
  });

  test('pasteLocalFile plain call sends all args', () async {
    late MethodCall seen;
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      seen = call;
      return docMap;
    });
    await platform.pasteLocalFile(
        '/tmp/src', 'content://dir', 'a.txt', 'text/plain');
    expect(seen.method, 'pasteLocalFile');
    expect(seen.arguments['name'], 'a.txt');
    expect(seen.arguments['overwrite'], false);
  });
}
