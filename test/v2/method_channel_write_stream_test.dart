// test/v2/method_channel_write_stream_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saf/src/v2/saf_method_channel.dart';

const docMap = {
  'uri': 'content://doc/new',
  'name': 'big.bin',
  'isDir': false,
  'length': 6,
  'lastModified': 2,
  'mimeType': 'application/octet-stream',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = MethodChannelSaf();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(
      () => messenger.setMockMethodCallHandler(platform.methodChannel, null));

  test('pumps chunks in order then ends the session', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'startWriteStream' => 'ws1',
        'writeChunk' => null,
        'endWriteStream' => docMap,
        _ => throw StateError('unexpected ${call.method}'),
      };
    });
    final source = Stream.fromIterable([
      [1, 2, 3],
      [4, 5, 6],
    ]);
    final d = await platform.writeFileStream(
        'content://dir', 'big.bin', 'application/octet-stream', source);
    expect(calls.map((c) => c.method).toList(),
        ['startWriteStream', 'writeChunk', 'writeChunk', 'endWriteStream']);
    expect(calls[1].arguments['data'], [1, 2, 3]);
    expect(calls[2].arguments['data'], [4, 5, 6]);
    expect(calls[1].arguments['session'], 'ws1');
    expect(d.length, 6);
  });

  test('aborts the session when the source stream errors', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      calls.add(call.method);
      return call.method == 'startWriteStream' ? 'ws2' : null;
    });
    final source = () async* {
      yield <int>[1];
      throw StateError('source broke');
    }();
    await expectLater(
      platform.writeFileStream('d', 'n', 'm', source),
      throwsA(isA<StateError>()),
    );
    expect(calls, ['startWriteStream', 'writeChunk', 'abortWriteStream']);
  });

  test('rejects overwrite+append before any channel call', () async {
    messenger.setMockMethodCallHandler(platform.methodChannel,
        (call) async => throw StateError('must not be called'));
    expect(
      () => platform.writeFileStream('d', 'n', 'm', const Stream.empty(),
          overwrite: true, append: true),
      throwsArgumentError,
    );
  });
}
