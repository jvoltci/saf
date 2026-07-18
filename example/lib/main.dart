import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:saf/saf.dart';

void main() => runApp(const MiniFileManagerApp());

class MiniFileManagerApp extends StatelessWidget {
  const MiniFileManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'saf 2.1 file manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const FileManagerPage(),
    );
  }
}

class FileManagerPage extends StatefulWidget {
  const FileManagerPage({super.key});

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  final _saf = Saf();

  SafDocumentFile? _dir;
  List<SafDocumentFile> _entries = const [];

  /// Cached per-URI thumbnail futures so scrolling doesn't refetch.
  final Map<String, Future<Uint8List?>> _thumbnails = {};

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Restore the last granted folder (if any) after the first frame so we
    // never call setState() during initState().
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreGrant());
  }

  bool _isImage(SafDocumentFile f) => f.mimeType?.startsWith('image/') ?? false;

  /// Runs [op], toggling the busy flag and surfacing failures as a SnackBar.
  Future<void> _run(Future<void> Function() op) async {
    setState(() => _busy = true);
    try {
      await op();
    } on SafException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Re-opens the most recently granted folder without prompting the user.
  Future<void> _restoreGrant() => _run(() async {
        final grants = await _saf.persistedPermissions();
        if (grants.isEmpty) return;
        final dir = await _saf.stat(grants.first.uri);
        if (dir == null) return; // grant points at a deleted document
        await _open(dir);
      });

  Future<void> _pickDirectory() => _run(() async {
        final dir = await _saf.pickDirectory(); // persisted by default
        if (dir == null) return; // user cancelled
        await _open(dir);
      });

  /// Loads and displays the contents of [dir].
  Future<void> _open(SafDocumentFile dir) async {
    final entries = await _saf.list(dir.uri);
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1; // folders first
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    setState(() {
      _dir = dir;
      _entries = entries;
      _thumbnails.clear();
    });
  }

  Future<void> _refresh() async {
    final dir = _dir;
    if (dir != null) await _open(dir);
  }

  Future<void> _writeSample() => _run(() async {
        final dir = _dir;
        if (dir == null) return;
        final stamp = DateTime.now().toIso8601String();
        final data = Uint8List.fromList(
          utf8.encode('Written by the saf 2.1 mini file manager at $stamp\n'),
        );
        final file = await _saf.writeFileBytes(
          dir.uri,
          'saf-sample.txt',
          'text/plain',
          data,
          overwrite: true,
        );
        _snack('Wrote ${file.name} (${file.length} B)');
        await _refresh();
      });

  Future<Uint8List?> _thumbnailFor(SafDocumentFile f) {
    return _thumbnails.putIfAbsent(f.uri, () async {
      try {
        return await _saf.thumbnail(f.uri, 128, 128, 80);
      } catch (_) {
        return null; // no provider thumbnail — fall back to an icon
      }
    });
  }

  void _showDetails(SafDocumentFile f) {
    showDialog<void>(
      context: context,
      builder: (_) => _DetailsDialog(saf: _saf, file: f),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dir = _dir;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SAF Mini File Manager'),
        actions: [
          if (dir != null)
            IconButton(
              tooltip: 'Refresh',
              onPressed: _busy ? null : () => _run(_refresh),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          _folderHeader(dir),
          const Divider(height: 1),
          Expanded(child: dir == null ? _emptyState() : _entryList()),
        ],
      ),
      floatingActionButton: dir == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _writeSample,
              icon: const Icon(Icons.note_add),
              label: const Text('Write sample'),
            ),
    );
  }

  Widget _folderHeader(SafDocumentFile? dir) {
    return ListTile(
      leading: const Icon(Icons.folder_open),
      title: Text(dir?.name ?? 'No folder selected'),
      subtitle: Text(
        dir == null
            ? 'Pick a folder to browse its contents'
            : '${_entries.length} item(s) - access granted & persisted',
      ),
      trailing: FilledButton.tonal(
        onPressed: _busy ? null : _pickDirectory,
        child: Text(dir == null ? 'Pick' : 'Change'),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_special_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'No folder selected yet.\nTap "Pick" to grant access to a folder.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryList() {
    if (_entries.isEmpty) {
      return const Center(child: Text('This folder is empty.'));
    }
    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final f = _entries[i];
        return ListTile(
          leading: _leading(f),
          title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            f.isDir
                ? 'directory'
                : '${_formatBytes(f.length)} - ${f.mimeType ?? 'unknown'}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showDetails(f),
        );
      },
    );
  }

  Widget _leading(SafDocumentFile f) {
    if (f.isDir) return const Icon(Icons.folder, size: 40);
    if (!_isImage(f)) return const Icon(Icons.insert_drive_file, size: 40);
    return SizedBox(
      width: 40,
      height: 40,
      child: FutureBuilder<Uint8List?>(
        future: _thumbnailFor(f),
        builder: (context, snap) {
          final bytes = snap.data;
          if (bytes == null) return const Icon(Icons.image, size: 40);
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              bytes,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          );
        },
      ),
    );
  }
}

/// Shows a document's metadata plus the live `/proc/self/fd/<fd>` path
/// obtained via [Saf.withFileDescriptor] (the descriptor auto-closes).
class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog({required this.saf, required this.file});

  final Saf saf;
  final SafDocumentFile file;

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  Future<String>? _fdPath;

  @override
  void initState() {
    super.initState();
    if (!widget.file.isDir) {
      _fdPath = widget.saf
          .withFileDescriptor(widget.file.uri, 'r', (fd) async => fd.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    return AlertDialog(
      title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field('Type', f.isDir ? 'directory' : (f.mimeType ?? 'unknown')),
          _field('Size', f.isDir ? '-' : _formatBytes(f.length)),
          const SizedBox(height: 12),
          Text(
            'File descriptor path',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          _fdPathView(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _fdPathView() {
    final future = _fdPath;
    if (future == null) return const Text('n/a for directories');
    return FutureBuilder<String>(
      future: future,
      builder: (context, snap) {
        switch (snap.connectionState) {
          case ConnectionState.done:
            if (snap.hasError) return Text('error: ${snap.error}');
            return SelectableText(
              snap.data ?? '',
              style: const TextStyle(fontFamily: 'monospace'),
            );
          default:
            return const Text('opening descriptor...');
        }
      },
    );
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(1)} ${units[i]}';
}
