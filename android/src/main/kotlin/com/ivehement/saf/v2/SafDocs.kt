package com.ivehement.saf.v2

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import java.io.FileNotFoundException

/**
 * Cursor-based DocumentsContract helpers. All listing/stat operations use a
 * single ContentResolver query with a full projection instead of
 * DocumentFile's one-query-per-property pattern.
 */
object SafDocs {
  private val PROJECTION = arrayOf(
    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
    DocumentsContract.Document.COLUMN_MIME_TYPE,
    DocumentsContract.Document.COLUMN_SIZE,
    DocumentsContract.Document.COLUMN_LAST_MODIFIED,
  )

  /**
   * Normalizes a URI to a *document* URI. A bare tree URI (as returned by
   * ACTION_OPEN_DOCUMENT_TREE, path `tree/<id>`) becomes its root document
   * URI; anything else is returned unchanged.
   */
  fun docUriOf(uri: Uri): Uri {
    val segments = uri.pathSegments
    return if (segments.size == 2 && segments[0] == "tree") {
      DocumentsContract.buildDocumentUriUsingTree(
        uri, DocumentsContract.getTreeDocumentId(uri)
      )
    } else uri
  }

  private fun rowToMap(c: Cursor, uriFor: (String) -> Uri): Map<String, Any?> {
    val docId = c.getString(0)
    val mime = c.getString(2)
    val isDir = mime == DocumentsContract.Document.MIME_TYPE_DIR
    return mapOf(
      "uri" to uriFor(docId).toString(),
      "name" to (c.getString(1) ?: ""),
      "isDir" to isDir,
      "length" to (if (c.isNull(3)) 0L else c.getLong(3)),
      "lastModified" to (if (c.isNull(4)) 0L else c.getLong(4)),
      "mimeType" to (if (isDir) null else mime),
    )
  }

  /** Metadata for [uri], or null when the document does not exist. */
  fun stat(context: Context, uri: Uri): Map<String, Any?>? {
    val doc = docUriOf(uri)
    return try {
      context.contentResolver.query(doc, PROJECTION, null, null, null)?.use { c ->
        if (c.moveToFirst()) rowToMap(c) { doc } else null
      }
    } catch (e: FileNotFoundException) {
      null
    } catch (e: IllegalArgumentException) {
      null
    } catch (e: UnsupportedOperationException) {
      null
    }
  }

  /** Children of [dirUri] with full metadata from one cursor. */
  fun listChildren(context: Context, dirUri: Uri): List<Map<String, Any?>> {
    val dirDoc = docUriOf(dirUri)
    val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
      dirDoc, DocumentsContract.getDocumentId(dirDoc)
    )
    val out = mutableListOf<Map<String, Any?>>()
    val cursor = context.contentResolver.query(childrenUri, PROJECTION, null, null, null)
      ?: throw SafNotFoundException("Cannot list $dirUri")
    cursor.use { c ->
      while (c.moveToNext()) {
        out.add(rowToMap(c) { id -> DocumentsContract.buildDocumentUriUsingTree(dirDoc, id) })
      }
    }
    return out
  }

  /** Resolves a descendant by name segments, or null if any segment is missing. */
  fun child(context: Context, dirUri: Uri, names: List<String>): Map<String, Any?>? {
    var current = stat(context, dirUri) ?: return null
    for (name in names) {
      val kids = listChildren(context, Uri.parse(current["uri"] as String))
      current = kids.firstOrNull { it["name"] == name } ?: return null
    }
    return current
  }

  /** Creates directory path [names] under [dirUri], returning the deepest dir. */
  fun mkdirp(context: Context, dirUri: Uri, names: List<String>): Map<String, Any?> {
    var currentUri = docUriOf(dirUri)
    for (name in names) {
      val existing = listChildren(context, currentUri).firstOrNull { it["name"] == name }
      currentUri = if (existing != null) {
        if (existing["isDir"] != true) {
          throw SafAlreadyExistsException("'$name' exists and is not a directory")
        }
        Uri.parse(existing["uri"] as String)
      } else {
        DocumentsContract.createDocument(
          context.contentResolver, currentUri,
          DocumentsContract.Document.MIME_TYPE_DIR, name
        ) ?: throw Exception("Failed to create directory '$name'")
      }
    }
    return stat(context, currentUri) ?: throw SafNotFoundException("mkdirp result missing")
  }

  /** Creates a new (possibly auto-renamed) document in [dirUri]. */
  fun createFile(context: Context, dirUri: Uri, mime: String, name: String): Uri =
    DocumentsContract.createDocument(context.contentResolver, docUriOf(dirUri), mime, name)
      ?: throw Exception("Failed to create '$name' in $dirUri")

  /** Deletes a document (recursively for directories, per provider). */
  fun delete(context: Context, uri: Uri) {
    val ok = DocumentsContract.deleteDocument(context.contentResolver, docUriOf(uri))
    if (!ok) throw Exception("Failed to delete $uri")
  }

  /** Renames a document, returning its (possibly new) URI. */
  fun rename(context: Context, uri: Uri, newName: String): Uri {
    val doc = docUriOf(uri)
    return DocumentsContract.renameDocument(context.contentResolver, doc, newName) ?: doc
  }

  /**
   * Copies raw contents from [src] into [dest], invoking [progress] with the
   * cumulative byte count.
   */
  fun copyContents(
    context: Context,
    src: Uri,
    dest: Uri,
    progress: ((Long) -> Unit)?,
  ) {
    val input = context.contentResolver.openInputStream(src)
      ?: throw SafNotFoundException("Cannot open input $src")
    input.use { ins ->
      val output = context.contentResolver.openOutputStream(dest, "wt")
        ?: throw Exception("Cannot open output $dest")
      output.use { outs ->
        val buf = ByteArray(1 shl 16)
        var total = 0L
        while (true) {
          val n = ins.read(buf)
          if (n < 0) break
          outs.write(buf, 0, n)
          total += n
          progress?.invoke(total)
        }
        outs.flush()
      }
    }
  }
}
