// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saf/saf.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SAF File Explorer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const FileExplorerPage(),
    );
  }
}

class FileExplorerPage extends StatefulWidget {
  const FileExplorerPage({super.key});

  @override
  State<FileExplorerPage> createState() => _FileExplorerPageState();
}

class _FileExplorerPageState extends State<FileExplorerPage> {
  List<String> _filePaths = [];
  String? _selectedFolderPath;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _requestStoragePermission();
  }

  Future<void> _requestStoragePermission() async {
    await Permission.storage.request();
  }

  Future<void> _selectFolderAndGetFiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _filePaths.clear();
    });

    try {
      // Use SAF to get dynamic directory permission (user chooses folder)
      bool? isGranted = await LegacySaf.getDynamicDirectoryPermission();

      if (isGranted == true) {
        // Get the list of persisted permission directories
        List<String>? directories =
            await LegacySaf.getPersistedPermissionDirectories();

        if (directories != null && directories.isNotEmpty) {
          // Use the most recently granted directory
          String selectedDirectory = directories.last;

          setState(() {
            _selectedFolderPath = selectedDirectory;
          });

          // Get all files recursively from the selected directory
          debugPrint(
            "DEBUG: Calling Saf.getFilesPathFor with directory: $selectedDirectory",
          );
          List<String>? filePaths = await LegacySaf.getFilesPathFor(
            selectedDirectory,
            fileType: "any", // Get all file types
          );

          debugPrint("DEBUG: Received filePaths: $filePaths");
          debugPrint("DEBUG: FilePaths length: ${filePaths?.length ?? 0}");

          if (filePaths != null) {
            setState(() {
              _filePaths = filePaths;
              _isLoading = false;
            });
            debugPrint("DEBUG: Updated UI with ${filePaths.length} files");
          } else {
            setState(() {
              _errorMessage = "No files found in the selected directory";
              _isLoading = false;
            });
            debugPrint("DEBUG: No files found, showing error message");
          }
        } else {
          setState(() {
            _errorMessage = "No directory permissions found";
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = "Permission denied or folder selection cancelled";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Error: ${e.toString()}";
        _isLoading = false;
      });
    }
  }

  Future<void> _clearPermissions() async {
    await LegacySaf.releasePersistedPermissions();
    setState(() {
      _filePaths.clear();
      _selectedFolderPath = null;
      _errorMessage = null;
    });
  }

  Widget _buildFileItem(String filePath) {
    String fileName = filePath.split('/').last;
    String fileExtension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';

    IconData iconData;
    Color iconColor;

    // Choose icon based on file extension
    switch (fileExtension) {
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'm4a':
        iconData = Icons.audiotrack;
        iconColor = Colors.blue;
        break;
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
        iconData = Icons.video_file;
        iconColor = Colors.red;
        break;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        iconData = Icons.image;
        iconColor = Colors.green;
        break;
      case 'pdf':
        iconData = Icons.picture_as_pdf;
        iconColor = Colors.red[700]!;
        break;
      case 'txt':
      case 'doc':
      case 'docx':
        iconData = Icons.description;
        iconColor = Colors.blue[700]!;
        break;
      default:
        iconData = Icons.insert_drive_file;
        iconColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2,
      child: ListTile(
        leading: Icon(iconData, color: iconColor, size: 32),
        title: Text(
          fileName,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: Text(
          filePath,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        dense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SAF File Explorer'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 2,
      ),
      body: Column(
        children: [
          // Header section with folder info and controls
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectedFolderPath != null) ...[
                  const Text(
                    'Selected Folder:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedFolderPath!,
                    style: const TextStyle(fontSize: 14, color: Colors.blue),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Found ${_filePaths.length} file(s)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.green,
                    ),
                  ),
                ] else ...[
                  const Text(
                    'No folder selected',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _selectFolderAndGetFiles,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.folder_open),
                      label: Text(_isLoading ? 'Loading...' : 'Choose Folder'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_selectedFolderPath != null)
                      ElevatedButton.icon(
                        onPressed: _clearPermissions,
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // File list section
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Scanning folder recursively...'),
                      ],
                    ),
                  )
                : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _filePaths.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Choose a folder to see all files recursively',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filePaths.length,
                    itemBuilder: (context, index) {
                      return _buildFileItem(_filePaths[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
