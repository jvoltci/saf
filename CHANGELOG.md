## 1.0.5

* **Removed the `permission_handler` dependency** from the plugin. It was unused
  by the library and only forced version conflicts on consumers (#36). Apps that
  still need it can add it directly.
* **Fixed external/removable storage support** (#41). `makeDirectoryPath` no
  longer assumes a `primary` volume, so SD-card and USB tree URIs (e.g.
  `.../tree/ABB8-7BD7%3A...`) are parsed correctly instead of throwing
  `RangeError`.
* **Fixed `getDirectoryPermission`** (#8, #27, #34). The permission the user
  actually grants is now adopted regardless of `isDynamic`, and persisted
  permissions are matched against the real granted URIs — so `isDynamic: false`
  works and access is remembered across app restarts instead of re-prompting
  every launch.
  * Behavior change: `isDynamic: false` no longer rejects a selection that does
    not exactly equal the requested directory (that check never worked and
    always returned `false`); it now adopts the granted directory.
* **Added binary-safe file reading** for non-media files on Android 13+ (#24).
  New `Saf.getFilesUri()` returns content URIs and `Saf.getDocumentContentAsBytes()`
  reads their raw bytes, avoiding the `PathAccessException` you get from reading
  absolute paths through `dart:io`.
* Modernized the Android toolchain: Android Gradle Plugin 8.9.1, Kotlin 2.1.0,
  `compileSdk` 35, `minSdk` 21, coroutines 1.9.0 (fixes #37-class build errors).
* Bumped `flutter_lints` to `^5.0.0`.

## 1.0.4

* Minor fixes and improvements
* Prepared for pub.dev publishing

## 1.0.1+4

* Updated permission_handler and misc

## 1.0.1+3

* Optimized and fixed minor bugs

## 1.0.1+2

* Path bug fix & description update

## 1.0.1+1

* Description small update

## 1.0.1

* Initial release.
* Support accessing files inside **hidden** folders (e.g. *.hidden_folder*)
* Android: Support caching & syncing files with app External files directory.