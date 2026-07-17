![saf](https://github.com/jvoltci/saf/blob/master/example/screenshots/saf_banner.png?raw=true)
<p align="center">
 <a href="https://pub.dartlang.org/packages/saf">
    <img alt="Saf" src="https://img.shields.io/pub/v/saf.svg">
  </a>
  <a href="https://github.com/jvoltci/saf/issues"><img src="https://img.shields.io/github/issues/jvoltci/saf">
  </a>
  <img src="https://img.shields.io/github/license/jvoltci/saf">
  <!-- <a href="https://github.com/jvoltci/saf/actions/workflows/main.yml">
    <img alt="CI pipeline status" src="https://github.com/jvoltci/saf/actions/workflows/main.yml/badge.svg">
  </a> -->
</p>

# Saf
Flutter plugin that leverages Storage Access Framework (SAF) API to get access and perform the operations on files and folders.

## Currently supported features
* Uses OS default native file explorer
* Access the **hidden** folder and files
* Accessing directories
* **Caching** the files inside the app External files directory
* **Syncing** the files of some directory with cached one
* Different default type filtering (media, image, video, audio or any)
* Support Android

If you have any feature that you want to see in this package, please feel free to issue a suggestion. 🎉

## Example App
#### Android
![Demo](https://github.com/jvoltci/saf/blob/master/example/screenshots/saf_example.gif)

## Usage

To use this plugin, add `saf` as a [dependency in your pubspec.yaml file](https://flutter.dev/docs/development/platform-integration/platform-channels).

### Initiate Saf with instance
```dart
Saf saf = Saf("~/some/path")
```

#### Directory Permission request
```dart
bool? isGranted = await saf.getDirectoryPermission(isDynamic: false);

if (isGranted != null && isGranted) {
  // Perform some file operations
} else {
  // failed to get the permission
}
```
#### Get the list of all the paths for the Granted Directories
```dart

bool? directoriesPath = await saf.getPersistedPermissionDirectories();

```
#### Get paths of all the files for current directory
```dart

List<String>? paths = await saf.getFilesPath(FileType.media);

```
#### Read a file's contents (works for non-media files on Android 13+)
> On Android 11+ reading the absolute paths from `getFilesPath` through
> `dart:io` `File` throws a `PathAccessException` for non-media files. Read the
> file via its SAF content URI instead:
```dart

List<String>? uris = await saf.getFilesUri();
if (uris != null && uris.isNotEmpty) {
  Uint8List? bytes = await Saf.getDocumentContentAsBytes(uris.first);
}

```
#### Cache the current directory
```dart

bool? isCached = await saf.cache();

if (isCached != null && isCached) {
  // Perform some file operations
} else {
  // failed to cache
}

```
#### Get the cached files' path for current directory
```dart

List<String>? cachedFilesPath = await saf.getCachedFilesPath();

```
#### Clear cache for the current directory
```dart

bool? isClear = await saf.clearCache();

```
#### Sync the current directory with the cached one
```dart

bool? isSynced = await saf.sync();

```
#### Release the persisted permission for current directory
```dart

bool? isReleased = await Saf.releasePersistedPermission();

```
#### Release the persisted permissions for all the granted directories
```dart

await Saf.releasePersistedPermissions();

```

## Documentation
See the **[Saf Wiki](https://github.com/jvoltci/saf/wiki)** for every detail on about how to install, setup and use it.

### Saf Wiki

1. [Installation](https://github.com/jvoltci/saf/wiki/Installation)
2. [Setup](https://github.com/jvoltci/saf/wiki/Setup)
   * [Android](https://github.com/jvoltci/saf/wiki/Setup#android)
3. [API](https://github.com/jvoltci/saf/wiki/api)
   * [Methods](https://github.com/jvoltci/saf/wiki/API#methods)
   * [Parameters](https://github.com/jvoltci/saf/wiki/API#parameters)
   * [Filters](https://github.com/jvoltci/saf/wiki/API#filters)
4. [FAQ](https://github.com/jvoltci/saf/wiki/FAQ)
5. [Troubleshooting](https://github.com/jvoltci/saf/wiki/Troubleshooting)

For full usage details refer to the **[Wiki](https://github.com/jvoltci/saf/wiki)** above.

## Getting Started

For help getting started with Flutter, view our online
[documentation](https://flutter.io/).

For help on editing plugin code, view the [documentation](https://flutter.io/platform-plugins/#edit-code).
