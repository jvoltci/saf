package com.jvoltci.saf.api

import android.graphics.Point
import android.net.Uri
import android.os.Build
import android.util.Log
import android.provider.DocumentsContract
import android.content.ContentResolver
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.jvoltci.saf.ROOT_CHANNEL
import com.jvoltci.saf.SafPlugin
import com.jvoltci.saf.plugin.*
import com.jvoltci.saf.api.utils.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import com.jvoltci.saf.api.utils.SafUtil

internal class DocumentsContractApi(private val plugin: SafPlugin) :
  MethodChannel.MethodCallHandler,
  Listenable,
  ActivityListener {
  private var channel: MethodChannel? = null
  private var util: SafUtil? = null

  companion object {
    private const val CHANNEL = "documentscontract"
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      BUID_CHILD_DOCUMENTS_URI_USING_TREE -> {
        try {
          val sourceTreeUri = Uri.parse(call.argument<String>("sourceTreeUriString"))
          val fileType = call.argument<String>("fileType")
        if(Build.VERSION.SDK_INT >= 21) {
            val contentResolver: ContentResolver = plugin.context.contentResolver
            var childrenUris = mutableListOf<String>()
            
            // Use the recursive traverseDirectoryEntries function to get all files recursively
            traverseDirectoryEntries(
              contentResolver,
              rootOnly = false, // Set to false to enable recursive traversal
              rootUri = sourceTreeUri,
              columns = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED
              )
            ) { data ->
              val metadata = data["metadata"] as Map<*, *>
              val fileData = data["data"] as Map<*, *>
              val isDirectory = metadata["isDirectory"] as Boolean?
              val uri = metadata["uri"] as String
              val mime = fileData[DocumentsContract.Document.COLUMN_MIME_TYPE] as String?
              
              // Only add files (not directories) that match the file type filter
              if (isDirectory == false) {
                val typeMatches = if (mime != null) {
                  fileType == "any" || mime.startsWith("image/") || mime.startsWith("audio/") || mime.startsWith("video/") || mime.startsWith("text/") || mime.startsWith("application/")
                } else {
                  fileType == "any"
                }
                if (typeMatches) {
                  childrenUris.add(uri)
                }
              }
            }
            
            result.success(childrenUris.toList())
          }
          else {
            result.notSupported(call.method, API_21)
          }
        }
        catch(e: Exception) {
          Log.e("BUID_CHILD_DOCUMENTS_PATH_USING_TREE_EXCEPTION: ", e.message!!)
          result.success(null)
        }
      }
      BUID_CHILD_DOCUMENTS_PATH_USING_TREE -> {
        try {
          val sourceTreeUri = Uri.parse(call.argument<String>("sourceTreeUriString"))
          val fileType = call.argument<String>("fileType")
          Log.d("SAF_DEBUG", "Starting BUID_CHILD_DOCUMENTS_PATH_USING_TREE with URI: $sourceTreeUri, fileType: $fileType")
          
          if(Build.VERSION.SDK_INT >= 21) {
            val contentResolver: ContentResolver = plugin.context.contentResolver
            var childrenPaths = mutableListOf<String>()
            var totalItemsFound = 0
            var filesFound = 0
            var directoriesFound = 0
            
            // Use the recursive traverseDirectoryEntries function to get all files recursively
            traverseDirectoryEntries(
              contentResolver,
              rootOnly = false, // Set to false to enable recursive traversal
              rootUri = sourceTreeUri,
              columns = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED
              )
            ) { data ->
              totalItemsFound++
              val metadata = data["metadata"] as Map<*, *>
              val fileData = data["data"] as Map<*, *>
              val isDirectory = metadata["isDirectory"] as Boolean?
              val uri = metadata["uri"] as String
              val mime = fileData[DocumentsContract.Document.COLUMN_MIME_TYPE] as String?
              
              Log.d("SAF_DEBUG", "Found item #$totalItemsFound: URI=$uri, isDirectory=$isDirectory, mime=$mime")
              
              if (isDirectory == true) {
                directoriesFound++
              } else if (isDirectory == false) {
                filesFound++
                // If MIME type is null, try to determine from file extension or accept if fileType is "any"
                val typeMatches = if (mime != null) {
                  fileType == "any" || mime.startsWith("image/") || mime.startsWith("audio/") || mime.startsWith("video/") || mime.startsWith("text/") || mime.startsWith("application/")
                } else {
                  // For null MIME types, check file extension or accept if fileType is "any"
                  if (fileType == "any") {
                    true
                  } else {
                    // Extract filename from URI and check extension
                    val fileName = uri.substringAfterLast("/").substringAfterLast("%2F")
                    val extension = fileName.substringAfterLast(".", "").lowercase()
                    when (extension) {
                      "mp3", "m4a", "m4b", "wav", "flac", "aac", "ogg" -> fileType == "audio"
                      "mp4", "avi", "mkv", "mov", "wmv" -> fileType == "video"
                      "jpg", "jpeg", "png", "gif", "bmp", "webp" -> fileType == "image"
                      "txt", "pdf", "doc", "docx" -> fileType == "text" || fileType == "application"
                      else -> fileType == "any"
                    }
                  }
                }
                
                Log.d("SAF_DEBUG", "File mime check: $mime, typeMatches: $typeMatches, fileType: $fileType, uri: $uri")
                
                if (typeMatches) {
                  val filePath = util?.getPath(Uri.parse(uri))
                  Log.d("SAF_DEBUG", "File path resolved: $filePath")
                  if (filePath != null) {
                    childrenPaths.add(filePath)
                    Log.d("SAF_DEBUG", "Added file to results: $filePath")
                  } else {
                    Log.w("SAF_DEBUG", "Could not resolve path for URI: $uri")
                  }
                } else {
                  Log.d("SAF_DEBUG", "File filtered out due to type mismatch")
                }
              }
            }
            
            Log.d("SAF_DEBUG", "Traversal complete. Total items: $totalItemsFound, Files: $filesFound, Directories: $directoriesFound, Paths added: ${childrenPaths.size}")
            result.success(childrenPaths.toList())
          }
          else {
            Log.e("SAF_DEBUG", "Android version not supported: ${Build.VERSION.SDK_INT}")
            result.notSupported(call.method, API_21)
          }
        }
        catch(e: Exception) {
          Log.e("BUID_CHILD_DOCUMENTS_PATH_USING_TREE_EXCEPTION", "Exception occurred: ${e.message}", e)
          result.success(null)
        }
      }
      GET_DOCUMENT_THUMBNAIL -> {
        if (Build.VERSION.SDK_INT >= API_21) {
          val rootUri = Uri.parse(call.argument("rootUri"))
          val documentId = call.argument<String>("documentId")
          val width = call.argument<Int>("width")!!
          val height = call.argument<Int>("height")!!

          val uri =
            DocumentsContract.buildDocumentUriUsingTree(rootUri, documentId)

          val bitmap = DocumentsContract.getDocumentThumbnail(
            plugin.context.contentResolver,
            uri,
            Point(width, height),
            null
          )

          CoroutineScope(Dispatchers.Default).launch {
            if (bitmap != null) {
              val base64 = bitmapToBase64(bitmap)

              val data = mapOf(
                "base64" to base64,
                "uri" to "$uri",
                "width" to bitmap.width,
                "height" to bitmap.height,
                "byteCount" to bitmap.byteCount,
                "density" to bitmap.density
              )

              launch(Dispatchers.Main) {
                result.success(data)
              }
            }
          }
        } else {
          result.notSupported(call.method, API_21)
        }
      }
      BUILD_DOCUMENT_URI_USING_TREE -> {
        val treeUri = Uri.parse(call.argument<String>("treeUriString"))
        val documentId = call.argument<String>("documentId")

        if (Build.VERSION.SDK_INT >= API_21) {
          val documentUri =
            DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)

          result.success("$documentUri")
        } else {
          result.notImplemented()
        }
      }
      BUILD_DOCUMENT_URI -> {
        val authority = call.argument<String>("authority")
        val documentId = call.argument<String>("documentId")

        if (Build.VERSION.SDK_INT >= API_21) {
          val documentUri = DocumentsContract.buildDocumentUri(authority,documentId)

          result.success("$documentUri")
        } else {
          result.notSupported(call.method, API_21)
        }
      }
      BUILD_TREE_DOCUMENT_URI -> {
        val authority = call.argument<String>("authority")
        val documentId = call.argument<String>("documentId")

        if (Build.VERSION.SDK_INT >= API_21) {
          val treeDocumentUri =
            DocumentsContract.buildTreeDocumentUri(authority, documentId)

          result.success("$treeDocumentUri")
        } else {
          result.notSupported(call.method, API_21)
        }
      }
    }
  }


  override fun startListening(binaryMessenger: BinaryMessenger) {
    if (channel != null) stopListening()

    channel = MethodChannel(binaryMessenger, "$ROOT_CHANNEL/$CHANNEL")
    util = SafUtil(plugin.context)
    channel?.setMethodCallHandler(this)
  }

  override fun stopListening() {
    if (channel == null) return

    channel?.setMethodCallHandler(null)
    channel = null
  }

  override fun startListeningToActivity() {
    /// Implement if needed
  }

  override fun stopListeningToActivity() {
    /// Implement if needed
  }
}
