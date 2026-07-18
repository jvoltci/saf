package com.ivehement.saf.v2

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import com.ivehement.saf.SafPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.OutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

private const val CHANNEL = "com.ivehement.plugins/saf/v2"
private const val PICK_DIRECTORY_CODE = 7101
private const val PICK_FILE_CODE = 7102
private const val PICK_FILES_CODE = 7103
private const val PROGRESS_INTERVAL_MS = 100L

class SafV2Api(private val plugin: SafPlugin) :
  MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {

  private var channel: MethodChannel? = null
  private var sessions: SessionManager? = null
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
  private val main = Handler(Looper.getMainLooper())
  private val pendingPicks =
    mutableMapOf<Int, Pair<MethodCall, MethodChannel.Result>>()

  private class WriteSession(
    val stream: OutputStream,
    val uri: Uri,
    val executor: ExecutorService,
  )

  private val writeSessions = mutableMapOf<String, WriteSession>()
  private var writeCounter = 0

  fun startListening(messenger: BinaryMessenger) {
    channel = MethodChannel(messenger, CHANNEL)
    channel?.setMethodCallHandler(this)
    sessions = SessionManager(messenger)
  }

  fun stopListening() {
    channel?.setMethodCallHandler(null)
    channel = null
    scope.cancel()
    synchronized(writeSessions) {
      writeSessions.values.forEach {
        runCatching { it.stream.close() }
        it.executor.shutdown()
      }
      writeSessions.clear()
    }
  }

  private val context get() = plugin.context
  private val activity: Activity? get() = plugin.binding?.activity

  /** Runs [block] on IO, posting success/typed error back on main. */
  private fun run(result: MethodChannel.Result, uri: String?, block: () -> Any?) {
    scope.launch {
      try {
        val value = block()
        main.post { result.success(value) }
      } catch (e: Throwable) {
        main.post { result.safError(e, uri) }
      }
    }
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "pickDirectory" -> startPick(PICK_DIRECTORY_CODE, call, result)
      "pickFile" -> startPick(PICK_FILE_CODE, call, result)
      "pickFiles" -> startPick(PICK_FILES_CODE, call, result)

      "persistedPermissions" -> run(result, null) {
        context.contentResolver.persistedUriPermissions.map {
          mapOf(
            "uri" to it.uri.toString(),
            "read" to it.isReadPermission,
            "write" to it.isWritePermission,
            "persistedTime" to it.persistedTime,
          )
        }
      }

      "releasePersistedPermission" -> {
        val uri = call.argument<String>("uri")!!
        run(result, uri) {
          val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
          runCatching {
            context.contentResolver.releasePersistableUriPermission(Uri.parse(uri), flags)
          }
          null
        }
      }

      "list" -> {
        val dirUri = call.argument<String>("dirUri")!!
        run(result, dirUri) { SafDocs.listChildren(context, Uri.parse(dirUri)) }
      }

      "stat" -> {
        val uri = call.argument<String>("uri")!!
        run(result, uri) { SafDocs.stat(context, Uri.parse(uri)) }
      }

      "child" -> {
        val dirUri = call.argument<String>("dirUri")!!
        val names = call.argument<List<String>>("names")!!
        run(result, dirUri) { SafDocs.child(context, Uri.parse(dirUri), names) }
      }

      "mkdirp" -> {
        val dirUri = call.argument<String>("dirUri")!!
        val names = call.argument<List<String>>("names")!!
        run(result, dirUri) { SafDocs.mkdirp(context, Uri.parse(dirUri), names) }
      }

      "delete" -> {
        val uri = call.argument<String>("uri")!!
        run(result, uri) { SafDocs.delete(context, Uri.parse(uri)); null }
      }

      "rename" -> {
        val uri = call.argument<String>("uri")!!
        val newName = call.argument<String>("newName")!!
        run(result, uri) {
          val renamed = SafDocs.rename(context, Uri.parse(uri), newName)
          SafDocs.stat(context, renamed) ?: throw SafNotFoundException("Renamed doc missing")
        }
      }

      "copyTo" -> copyOrMove(call, result, move = false)
      "moveTo" -> copyOrMove(call, result, move = true)

      "readFileBytes" -> {
        val uri = call.argument<String>("uri")!!
        val start = call.argument<Number>("start")?.toLong() ?: 0L
        val count = call.argument<Number>("count")?.toInt()
        run(result, uri) {
          val input = context.contentResolver.openInputStream(Uri.parse(uri))
            ?: throw SafNotFoundException("Cannot open $uri")
          input.use { ins ->
            skipFully(ins, start)
            if (count == null) ins.readBytes()
            else {
              val buf = ByteArray(count)
              var off = 0
              while (off < count) {
                val n = ins.read(buf, off, count - off)
                if (n < 0) break
                off += n
              }
              buf.copyOf(off)
            }
          }
        }
      }

      "readFileStream" -> {
        val uri = call.argument<String>("uri")!!
        val start = call.argument<Number>("start")?.toLong() ?: 0L
        val bufferSize = call.argument<Number>("bufferSize")!!.toInt()
        val (session, sink) = sessions!!.create()
        result.success(session)
        scope.launch {
          try {
            val input = context.contentResolver.openInputStream(Uri.parse(uri))
              ?: throw SafNotFoundException("Cannot open $uri")
            input.use { ins ->
              skipFully(ins, start)
              val buf = ByteArray(bufferSize)
              while (!sink.cancelled) {
                val n = ins.read(buf)
                if (n < 0) break
                sink.success(buf.copyOf(n))
              }
            }
            sink.endOfStream()
          } catch (e: Throwable) {
            sink.error(errorCodeOf(e), e.message ?: e.toString(), mapOf("uri" to uri))
            sink.endOfStream()
          }
        }
      }

      "startWalk" -> {
        val dirUri = call.argument<String>("dirUri")!!
        val (session, sink) = sessions!!.create()
        result.success(session)
        scope.launch {
          try {
            val stack = ArrayDeque<Pair<Uri, String>>()
            stack.addLast(Uri.parse(dirUri) to "")
            while (stack.isNotEmpty() && !sink.cancelled) {
              val (dir, prefix) = stack.removeLast()
              for (kid in SafDocs.listChildren(context, dir)) {
                if (sink.cancelled) break
                val rel = if (prefix.isEmpty()) kid["name"] as String
                          else "$prefix/${kid["name"]}"
                sink.success(mapOf("file" to kid, "relativePath" to rel))
                if (kid["isDir"] == true) {
                  stack.addLast(Uri.parse(kid["uri"] as String) to rel)
                }
              }
            }
            sink.endOfStream()
          } catch (e: Throwable) {
            sink.error(errorCodeOf(e), e.message ?: e.toString(), mapOf("uri" to dirUri))
            sink.endOfStream()
          }
        }
      }

      "writeFileBytes" -> {
        val dirUri = call.argument<String>("dirUri")!!
        val name = call.argument<String>("name")!!
        val mime = call.argument<String>("mime")!!
        val data = call.argument<ByteArray>("data")!!
        val overwrite = call.argument<Boolean>("overwrite") ?: false
        val append = call.argument<Boolean>("append") ?: false
        run(result, dirUri) {
          val target = resolveWriteTarget(dirUri, name, mime, overwrite, append)
          val mode = if (append) "wa" else "wt"
          val out = context.contentResolver.openOutputStream(target, mode)
            ?: throw Exception("Cannot open output $target")
          out.use { it.write(data); it.flush() }
          SafDocs.stat(context, target) ?: throw SafNotFoundException("Written doc missing")
        }
      }

      "startWriteStream" -> {
        val dirUri = call.argument<String>("dirUri")!!
        val name = call.argument<String>("name")!!
        val mime = call.argument<String>("mime")!!
        val overwrite = call.argument<Boolean>("overwrite") ?: false
        val append = call.argument<Boolean>("append") ?: false
        run(result, dirUri) {
          val target = resolveWriteTarget(dirUri, name, mime, overwrite, append)
          val mode = if (append) "wa" else "wt"
          val out = context.contentResolver.openOutputStream(target, mode)
            ?: throw Exception("Cannot open output $target")
          val id = synchronized(writeSessions) {
            val id = "w${writeCounter++}"
            writeSessions[id] =
              WriteSession(out, target, Executors.newSingleThreadExecutor())
            id
          }
          id
        }
      }

      "writeChunk" -> {
        val id = call.argument<String>("session")!!
        val data = call.argument<ByteArray>("data")!!
        val session = synchronized(writeSessions) { writeSessions[id] }
        if (session == null) {
          result.safError(SafNotFoundException("No write session $id"), null)
        } else {
          session.executor.execute {
            try {
              session.stream.write(data)
              main.post { result.success(null) }
            } catch (e: Throwable) {
              main.post { result.safError(e, session.uri.toString()) }
            }
          }
        }
      }

      "endWriteStream" -> {
        val id = call.argument<String>("session")!!
        val session = synchronized(writeSessions) { writeSessions.remove(id) }
        if (session == null) {
          result.safError(SafNotFoundException("No write session $id"), null)
        } else {
          session.executor.execute {
            try {
              session.stream.flush()
              session.stream.close()
              val map = SafDocs.stat(context, session.uri)
              main.post {
                if (map == null) {
                  result.safError(SafNotFoundException("Written doc missing"), session.uri.toString())
                } else {
                  result.success(map)
                }
              }
            } catch (e: Throwable) {
              main.post { result.safError(e, session.uri.toString()) }
            } finally {
              session.executor.shutdown()
            }
          }
        }
      }

      "abortWriteStream" -> {
        val id = call.argument<String>("session")!!
        val session = synchronized(writeSessions) { writeSessions.remove(id) }
        if (session == null) {
          result.success(null)
        } else {
          session.executor.execute {
            runCatching { session.stream.close() }
            runCatching { SafDocs.delete(context, session.uri) }
            session.executor.shutdown()
            main.post { result.success(null) }
          }
        }
      }

      "copyToLocalFile" -> {
        val srcUri = call.argument<String>("srcUri")!!
        val destPath = call.argument<String>("destPath")!!
        val withProgress = call.argument<Boolean>("withProgress") ?: false
        progressOp(result, withProgress, srcUri) { emit ->
          val total = SafDocs.stat(context, Uri.parse(srcUri))?.get("length") as? Long
          val name = File(destPath).name
          val input = context.contentResolver.openInputStream(Uri.parse(srcUri))
            ?: throw SafNotFoundException("Cannot open $srcUri")
          input.use { ins ->
            FileOutputStream(destPath).use { outs ->
              val buf = ByteArray(1 shl 16)
              var done = 0L
              while (true) {
                val n = ins.read(buf)
                if (n < 0) break
                outs.write(buf, 0, n)
                done += n
                emit?.invoke(done, total, name)
              }
            }
          }
          null
        }
      }

      "pasteLocalFile" -> {
        val srcPath = call.argument<String>("srcPath")!!
        val destDirUri = call.argument<String>("destDirUri")!!
        val name = call.argument<String>("name")!!
        val mime = call.argument<String>("mime")!!
        val overwrite = call.argument<Boolean>("overwrite") ?: false
        val withProgress = call.argument<Boolean>("withProgress") ?: false
        progressOp(result, withProgress, destDirUri) { emit ->
          val src = File(srcPath)
          if (!src.exists()) throw SafNotFoundException("No local file $srcPath")
          val total = src.length()
          val target = resolveWriteTarget(destDirUri, name, mime, overwrite, append = false)
          FileInputStream(src).use { ins ->
            val out = context.contentResolver.openOutputStream(target, "wt")
              ?: throw Exception("Cannot open output $target")
            out.use { outs ->
              val buf = ByteArray(1 shl 16)
              var done = 0L
              while (true) {
                val n = ins.read(buf)
                if (n < 0) break
                outs.write(buf, 0, n)
                done += n
                emit?.invoke(done, total, name)
              }
              outs.flush()
            }
          }
          SafDocs.stat(context, target) ?: throw SafNotFoundException("Pasted doc missing")
        }
      }

      else -> result.notImplemented()
    }
  }

  /** Existing-child + overwrite/append/auto-rename resolution for writes. */
  private fun resolveWriteTarget(
    dirUri: String,
    name: String,
    mime: String,
    overwrite: Boolean,
    append: Boolean,
  ): Uri {
    val dir = Uri.parse(dirUri)
    val existing = SafDocs.child(context, dir, listOf(name))
    return when {
      existing != null && (overwrite || append) -> Uri.parse(existing["uri"] as String)
      else -> SafDocs.createFile(context, dir, mime, name)
    }
  }

  /**
   * Runs [block] either as a plain call (progress emitter null) or as a
   * progress session that returns the session id immediately and reports
   * {progress,done} events, throttled to [PROGRESS_INTERVAL_MS].
   */
  private fun progressOp(
    result: MethodChannel.Result,
    withProgress: Boolean,
    uri: String,
    block: (emit: ((Long, Long?, String) -> Unit)?) -> Any?,
  ) {
    if (!withProgress) {
      run(result, uri) { block(null) }
      return
    }
    val (session, sink) = sessions!!.create()
    result.success(session)
    scope.launch {
      try {
        var lastEmit = 0L
        val file = block { done, total, name ->
          val now = System.currentTimeMillis()
          if (now - lastEmit >= PROGRESS_INTERVAL_MS) {
            lastEmit = now
            sink.success(mapOf(
              "type" to "progress",
              "bytesDone" to done,
              "totalBytes" to total,
              "currentName" to name,
            ))
          }
        }
        sink.success(mapOf("type" to "done", "file" to file))
        sink.endOfStream()
      } catch (e: Throwable) {
        sink.error(errorCodeOf(e), e.message ?: e.toString(), mapOf("uri" to uri))
        sink.endOfStream()
      }
    }
  }

  private fun copyOrMove(call: MethodCall, result: MethodChannel.Result, move: Boolean) {
    val uriStr = call.argument<String>("uri")!!
    val destDirStr = call.argument<String>("destDirUri")!!
    val withProgress = call.argument<Boolean>("withProgress") ?: false
    progressOp(result, withProgress, uriStr) { emit ->
      val srcMap = SafDocs.stat(context, Uri.parse(uriStr))
        ?: throw SafNotFoundException("Source missing: $uriStr")
      var cumulative = 0L
      val copied = copyRecursive(srcMap, Uri.parse(destDirStr)) { fileDone, name, fileTotal ->
        emit?.invoke(cumulative + fileDone,
          if (srcMap["isDir"] == true) null else fileTotal, name)
      }.also { root ->
        // Track cumulative bytes across files for directory copies.
        cumulative = 0L
        root
      }
      if (move) SafDocs.delete(context, Uri.parse(uriStr))
      copied
    }
  }

  /**
   * Copies [srcMap] (file or directory) into [destDir]; returns the map of the
   * created root document. [onFileProgress] gets per-file byte counts.
   */
  private fun copyRecursive(
    srcMap: Map<String, Any?>,
    destDir: Uri,
    onFileProgress: (done: Long, name: String, total: Long?) -> Unit,
  ): Map<String, Any?> {
    val name = srcMap["name"] as String
    return if (srcMap["isDir"] == true) {
      val newDir = SafDocs.mkdirp(context, destDir, listOf(name))
      for (kid in SafDocs.listChildren(context, Uri.parse(srcMap["uri"] as String))) {
        copyRecursive(kid, Uri.parse(newDir["uri"] as String), onFileProgress)
      }
      newDir
    } else {
      val mime = srcMap["mimeType"] as? String ?: "application/octet-stream"
      val target = SafDocs.createFile(context, destDir, mime, name)
      val total = srcMap["length"] as? Long
      SafDocs.copyContents(context, Uri.parse(srcMap["uri"] as String), target) { done ->
        onFileProgress(done, name, total)
      }
      SafDocs.stat(context, target) ?: throw SafNotFoundException("Copied doc missing")
    }
  }

  // Pickers -------------------------------------------------------------------

  private fun startPick(code: Int, call: MethodCall, result: MethodChannel.Result) {
    val act = activity
    if (act == null) {
      result.safError(Exception("Plugin not attached to an Activity"), null)
      return
    }
    synchronized(pendingPicks) {
      if (pendingPicks.containsKey(code)) {
        result.safError(Exception("Another picker is already open"), null)
        return
      }
      pendingPicks[code] = call to result
    }
    val intent = when (code) {
      PICK_DIRECTORY_CODE -> Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
      else -> Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = "*/*"
        val mimeTypes = call.argument<List<String>>("mimeTypes")
        if (!mimeTypes.isNullOrEmpty()) {
          putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
        }
        if (code == PICK_FILES_CODE) putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
      }
    }
    val initialUri = call.argument<String>("initialUri")
    if (initialUri != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(initialUri))
    }
    act.startActivityForResult(intent, code)
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    val pending = synchronized(pendingPicks) { pendingPicks.remove(requestCode) } ?: return false
    val (call, result) = pending
    if (resultCode != Activity.RESULT_OK || data == null) {
      main.post {
        result.success(if (requestCode == PICK_FILES_CODE) emptyList<Any>() else null)
      }
      return true
    }
    val persistable = call.argument<Boolean>("persistablePermission") ?: false
    val write = call.argument<Boolean>("writePermission") ?: true
    scope.launch {
      try {
        val value: Any? = when (requestCode) {
          PICK_DIRECTORY_CODE -> {
            val tree = data.data!!
            if (persistable) takePersistable(tree, write)
            SafDocs.stat(context, tree)
          }
          PICK_FILE_CODE -> {
            val uri = data.data!!
            if (persistable) takePersistable(uri, write = true)
            SafDocs.stat(context, uri)
          }
          else -> {
            val uris = mutableListOf<Uri>()
            val clip = data.clipData
            if (clip != null) {
              for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
            } else {
              data.data?.let { uris.add(it) }
            }
            uris.mapNotNull { uri ->
              if (persistable) takePersistable(uri, write = true)
              SafDocs.stat(context, uri)
            }
          }
        }
        main.post { result.success(value) }
      } catch (e: Throwable) {
        main.post { result.safError(e, data.data?.toString()) }
      }
    }
    return true
  }

  private fun takePersistable(uri: Uri, write: Boolean) {
    var flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
    if (write) flags = flags or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    runCatching { context.contentResolver.takePersistableUriPermission(uri, flags) }
  }

  private fun skipFully(input: java.io.InputStream, count: Long) {
    var remaining = count
    while (remaining > 0) {
      val skipped = input.skip(remaining)
      if (skipped <= 0) break
      remaining -= skipped
    }
  }
}
