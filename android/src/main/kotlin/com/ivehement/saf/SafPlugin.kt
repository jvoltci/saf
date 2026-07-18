package com.ivehement.saf

import com.ivehement.saf.api.StorageAccessFramework
import com.ivehement.saf.v2.SafV2Api

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import android.os.*
import android.os.Build.VERSION
import android.util.Log
import android.content.Context
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.BinaryMessenger

const val ROOT_CHANNEL = "com.ivehement.plugins/saf"

class SafPlugin: FlutterPlugin, ActivityAware {
  
    /**
     * `DocumentFile` API channel
     */
    private val storageAccessFrameworkApi = StorageAccessFramework(this)

    /** v2 single-class API channel */
    private var safV2Api: SafV2Api? = null

    lateinit var context: Context
    var binding: ActivityPluginBinding? = null
  
    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
      context = flutterPluginBinding.applicationContext
      /** Setup `StorageAccessFramework` API */
      storageAccessFrameworkApi.startListening(flutterPluginBinding.binaryMessenger)
      safV2Api = SafV2Api(this)
      safV2Api?.startListening(flutterPluginBinding.binaryMessenger)
    }
  
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
      this.binding = binding
  
      storageAccessFrameworkApi.startListeningToActivity()
      safV2Api?.let { binding.addActivityResultListener(it) }
    }
  
    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
      storageAccessFrameworkApi.stopListening()
      safV2Api?.stopListening()
      safV2Api = null
    }
  
    override fun onDetachedFromActivityForConfigChanges() {
      storageAccessFrameworkApi.stopListeningToActivity()
    }
  
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
      this.binding = binding
      safV2Api?.let { binding.addActivityResultListener(it) }
    }
  
    override fun onDetachedFromActivity() {
      binding = null
    }
}