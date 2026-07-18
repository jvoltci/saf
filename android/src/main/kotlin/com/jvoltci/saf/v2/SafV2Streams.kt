package com.jvoltci.saf.v2

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * An EventSink that buffers events until a Dart listener attaches, then
 * replays them. Solves the subscribe-after-invoke race for session channels.
 * Also exposes [cancelled] so producers can stop early when Dart cancels.
 */
class QueuingEventSink : EventChannel.EventSink {
  private var delegate: EventChannel.EventSink? = null
  private val buffer = mutableListOf<Any>()
  private var done = false

  @Volatile
  var cancelled = false
    private set

  private class EndOfStream
  private class ErrorEvent(val code: String, val message: String?, val details: Any?)

  @Synchronized
  fun setDelegate(sink: EventChannel.EventSink?) {
    delegate = sink
    if (sink == null) {
      cancelled = true
      return
    }
    for (event in buffer) dispatch(event, sink)
    buffer.clear()
  }

  @Synchronized
  override fun success(event: Any?) = enqueue(event ?: Unit)

  @Synchronized
  override fun error(code: String, message: String?, details: Any?) =
    enqueue(ErrorEvent(code, message, details))

  @Synchronized
  override fun endOfStream() {
    enqueue(EndOfStream())
    done = true
  }

  private fun enqueue(event: Any) {
    if (done) return
    val sink = delegate
    if (sink != null) dispatch(event, sink) else buffer.add(event)
  }

  private fun dispatch(event: Any, sink: EventChannel.EventSink) {
    when (event) {
      is EndOfStream -> sink.endOfStream()
      is ErrorEvent -> sink.error(event.code, event.message, event.details)
      is Unit -> sink.success(null)
      else -> sink.success(event)
    }
  }
}

/** An EventSink wrapper that always delivers on the Android main thread. */
class MainThreadEventSink(private val inner: EventChannel.EventSink) :
  EventChannel.EventSink {
  private val handler = Handler(Looper.getMainLooper())

  override fun success(event: Any?) = runOnMain { inner.success(event) }
  override fun error(code: String, message: String?, details: Any?) =
    runOnMain { inner.error(code, message, details) }
  override fun endOfStream() = runOnMain { inner.endOfStream() }

  private fun runOnMain(block: () -> Unit) {
    if (Looper.myLooper() == Looper.getMainLooper()) block() else handler.post(block)
  }
}

/** Creates one EventChannel per streaming session. */
class SessionManager(private val messenger: BinaryMessenger) {
  private var counter = 0

  @Synchronized
  fun create(): Pair<String, QueuingEventSink> {
    val id = "saf_v2_${System.nanoTime()}_${counter++}"
    val sink = QueuingEventSink()
    val channel = EventChannel(messenger, "com.ivehement.plugins/saf/v2/events/$id")
    channel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink.setDelegate(MainThreadEventSink(events))
      }

      override fun onCancel(arguments: Any?) {
        sink.setDelegate(null)
        // Unregister the per-session handler so it doesn't leak on the messenger.
        channel.setStreamHandler(null)
      }
    })
    return id to sink
  }
}
