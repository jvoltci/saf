import 'package:flutter/services.dart';

/// Base class for all failures thrown by the v2 `Saf` API.
sealed class SafException implements Exception {
  /// URI of the document involved, when known ('' otherwise).
  final String uri;

  /// Human-readable failure description.
  final String message;

  const SafException(this.uri, this.message);

  @override
  String toString() => '$runtimeType($uri): $message';
}

/// The app lacks (persisted) permission for the target URI.
class SafPermissionException extends SafException {
  const SafPermissionException(super.uri, super.message);
}

/// The target document does not exist.
class SafNotFoundException extends SafException {
  const SafNotFoundException(super.uri, super.message);
}

/// A document with the same name already exists.
class SafAlreadyExistsException extends SafException {
  const SafAlreadyExistsException(super.uri, super.message);
}

/// Any other I/O failure.
class SafIoException extends SafException {
  const SafIoException(super.uri, super.message);
}

/// Converts a [PlatformException] raised by the native side into the
/// typed [SafException] hierarchy.
SafException mapPlatformException(PlatformException e) {
  final details = e.details;
  final uri = (details is Map ? details['uri'] : null)?.toString() ?? '';
  final message = e.message ?? e.code;
  return switch (e.code) {
    'permission' => SafPermissionException(uri, message),
    'not_found' => SafNotFoundException(uri, message),
    'already_exists' => SafAlreadyExistsException(uri, message),
    _ => SafIoException(uri, message),
  };
}
