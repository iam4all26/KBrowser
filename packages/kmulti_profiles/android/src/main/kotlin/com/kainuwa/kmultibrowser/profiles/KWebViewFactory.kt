package com.kainuwa.kmultibrowser.profiles

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class KWebViewFactory(
    private val messenger: BinaryMessenger,
    private val fileChooser: FileChooserBridge
) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val profile = params?.get("profile") as? String ?: ""
        return KWebView(context, viewId, messenger, profile, fileChooser)
    }
}
