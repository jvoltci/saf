package com.jvoltci.saf.api

import io.flutter.plugin.common.*
import com.jvoltci.saf.SafPlugin
import android.util.Log
import com.jvoltci.saf.plugin.ActivityListener
import com.jvoltci.saf.plugin.Listenable

class StorageAccessFramework(plugin: SafPlugin) :
  Listenable,
  ActivityListener {
  private val documentFileApi = DocumentFileApi(plugin)
  private val documentsContractApi = DocumentsContractApi(plugin)

  override fun startListening(binaryMessenger: BinaryMessenger) {
    documentFileApi.startListening(binaryMessenger)
    documentsContractApi.startListening(binaryMessenger)
  }

  override fun stopListening() {
    documentFileApi.stopListening()
    documentsContractApi.stopListening()
  }

  override fun startListeningToActivity() {
    documentFileApi.startListeningToActivity()
    documentsContractApi.startListeningToActivity()
  }

  override fun stopListeningToActivity() {
    documentFileApi.stopListeningToActivity()
    documentsContractApi.stopListeningToActivity()
  }
}
