/// Flutter plugin for the Android Storage Access Framework (SAF):
/// directory/file pickers, persisted permissions, file management with
/// recursive walk, streamed read/write with progress, and local-file
/// bridging — in a single [Saf] class.
///
/// See the [project page](https://jvoltci.github.io/saf/) for usage examples.
library;

export 'src/v2/exceptions.dart' hide mapPlatformException;
export 'src/v2/models.dart';
export 'src/v2/saf.dart';
export 'src/v2/saf_platform_interface.dart' show SafPlatform;

// Legacy 1.x API — deprecated, removed in 3.0.0.
export 'src/storage_access_framework/saf.dart';
export 'src/storage_access_framework/file_types.dart';
