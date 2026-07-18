import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:saf/saf.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'saf 2.0 demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _saf = Saf();
  SafDocumentFile? _dir;
  List<SafDocumentFile> _children = const [];
  final _log = <String>[];
  double? _progress;

  void _print(String line) => setState(() => _log.insert(0, line));

  Future<void> _guard(String label, Future<void> Function() op) async {
    try {
      await op();
    } on SafException catch (e) {
      _print('✗ $label: $e');
    } catch (e) {
      _print('✗ $label: $e');
    }
  }

  Future<void> _pickDirectory() => _guard('pick', () async {
        final dir = await _saf.pickDirectory();
        if (dir == null) {
          _print('picker cancelled');
          return;
        }
        setState(() => _dir = dir);
        _print('✓ picked ${dir.name}');
        await _refresh();
      });

  Future<void> _refresh() => _guard('list', () async {
        final kids = await _saf.list(_dir!.uri);
        setState(() => _children = kids);
        _print('✓ listed ${kids.length} entries');
      });

  Future<void> _restorePermission() => _guard('restore', () async {
        final grants = await _saf.persistedPermissions();
        if (grants.isEmpty) {
          _print('no persisted permissions');
          return;
        }
        final dir = await _saf.stat(grants.first.uri);
        if (dir == null) {
          _print('persisted grant points at a missing document');
          return;
        }
        setState(() => _dir = dir);
        _print('✓ restored ${dir.name} without prompting');
        await _refresh();
      });

  Future<void> _writeDemoFiles() => _guard('write', () async {
        final bytes = Uint8List.fromList(utf8.encode('Hello from saf 2.0!\n'));
        final f1 = await _saf.writeFileBytes(
            _dir!.uri, 'saf-demo.txt', 'text/plain', bytes,
            overwrite: true);
        _print('✓ wrote ${f1.name} (${f1.length} B)');
        final chunks =
            Stream.fromIterable(List.generate(50, (i) => utf8.encode('line $i\n')));
        final f2 = await _saf.writeFileStream(
            _dir!.uri, 'saf-demo-stream.txt', 'text/plain', chunks,
            overwrite: true);
        _print('✓ streamed ${f2.name} (${f2.length} B)');
        await _refresh();
      });

  Future<void> _readBack() => _guard('read', () async {
        final f = await _saf.child(_dir!.uri, ['saf-demo.txt']);
        if (f == null) {
          _print('saf-demo.txt not found — write first');
          return;
        }
        final bytes = await _saf.readFileBytes(f.uri);
        _print('✓ read ${bytes.length} B: '
            '"${utf8.decode(bytes).trim()}"');
        final stream = await _saf.readFileStream(f.uri, bufferSize: 8);
        final n = (await stream.toList()).length;
        _print('✓ read again as $n stream chunks');
      });

  Future<void> _walk() => _guard('walk', () async {
        var count = 0;
        await for (final entry in _saf.walk(_dir!.uri)) {
          count++;
          if (count <= 5) _print('  ${entry.relativePath}');
        }
        _print('✓ walked $count descendants (first 5 shown)');
      });

  Future<void> _copyWithProgress() => _guard('copy', () async {
        final f = await _saf.child(_dir!.uri, ['saf-demo.txt']);
        if (f == null) {
          _print('saf-demo.txt not found — write first');
          return;
        }
        final backups = await _saf.mkdirp(_dir!.uri, ['saf-backups']);
        final copied = await _saf.copyTo(f.uri, backups.uri, onProgress: (p) {
          setState(() => _progress =
              p.totalBytes == null ? null : p.bytesDone / p.totalBytes!);
        });
        setState(() => _progress = null);
        _print('✓ copied to saf-backups/${copied.name}');
        await _refresh();
      });

  Future<void> _cleanUp() => _guard('delete', () async {
        for (final name in ['saf-demo.txt', 'saf-demo-stream.txt', 'saf-backups']) {
          final f = await _saf.child(_dir!.uri, [name]);
          if (f != null) await _saf.delete(f.uri);
        }
        _print('✓ demo files deleted');
        await _refresh();
      });

  @override
  Widget build(BuildContext context) {
    final hasDir = _dir != null;
    return Scaffold(
      appBar: AppBar(title: const Text('saf 2.0 kitchen sink')),
      body: Column(
        children: [
          if (_progress != null) LinearProgressIndicator(value: _progress),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                    onPressed: _pickDirectory, child: const Text('Pick dir')),
                FilledButton.tonal(
                    onPressed: _restorePermission,
                    child: const Text('Restore permission')),
                FilledButton.tonal(
                    onPressed: hasDir ? _writeDemoFiles : null,
                    child: const Text('Write')),
                FilledButton.tonal(
                    onPressed: hasDir ? _readBack : null,
                    child: const Text('Read')),
                FilledButton.tonal(
                    onPressed: hasDir ? _walk : null, child: const Text('Walk')),
                FilledButton.tonal(
                    onPressed: hasDir ? _copyWithProgress : null,
                    child: const Text('Copy+progress')),
                FilledButton.tonal(
                    onPressed: hasDir ? _cleanUp : null,
                    child: const Text('Clean up')),
              ],
            ),
          ),
          if (hasDir)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('${_dir!.name} — ${_children.length} entries',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final f in _children)
                  ListTile(
                    dense: true,
                    leading: Icon(f.isDir ? Icons.folder : Icons.description),
                    title: Text(f.name),
                    subtitle: Text(f.isDir
                        ? 'directory'
                        : '${f.length} B · ${f.mimeType ?? 'unknown'}'),
                  ),
                const Divider(),
                for (final line in _log)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 2),
                    child: Text(line,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
