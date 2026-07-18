package com.jvoltci.saf.v2

import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException

/** Thrown when a document that must not exist already does. */
class SafAlreadyExistsException(message: String) : Exception(message)

/** Thrown when a document that must exist does not. */
class SafNotFoundException(message: String) : Exception(message)

/** Maps a throwable to one of the four stable v2 error codes. */
fun errorCodeOf(e: Throwable): String = when (e) {
  is SafNotFoundException, is FileNotFoundException -> "not_found"
  is SafAlreadyExistsException -> "already_exists"
  is SecurityException -> "permission"
  else -> "io"
}

/** Completes a method-channel result with a typed v2 error. */
fun MethodChannel.Result.safError(e: Throwable, uri: String?) {
  error(errorCodeOf(e), e.message ?: e.toString(), mapOf("uri" to (uri ?: "")))
}
