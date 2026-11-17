package com.kainuwa.kmultibrowser.profiles

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import io.flutter.plugin.common.PluginRegistry

/**
 * Opens the system file picker for <input type="file"> and returns the chosen
 * files to the WebView that asked. Shared by all WebViews of the plugin.
 */
class FileChooserBridge : PluginRegistry.ActivityResultListener {
    var activity: Activity? = null
    private var pending: ValueCallback<Array<Uri>>? = null

    /** Returns false if the picker could not be opened (the callback is then not used). */
    fun launch(
        params: WebChromeClient.FileChooserParams,
        callback: ValueCallback<Array<Uri>>
    ): Boolean {
        val act = activity ?: return false
        // A previous request that never got an answer is cancelled.
        pending?.onReceiveValue(null)
        pending = null
        return try {
            val intent = params.createIntent()
            pending = callback
            act.startActivityForResult(intent, REQUEST_CODE)
            true
        } catch (e: Throwable) {
            pending = null
            false
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val cb = pending ?: return true
        pending = null
        cb.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data))
        return true
    }

    companion object {
        const val REQUEST_CODE = 0x4B31
    }
}
