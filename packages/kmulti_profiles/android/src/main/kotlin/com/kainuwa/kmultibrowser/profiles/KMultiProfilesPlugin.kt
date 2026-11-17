package com.kainuwa.kmultibrowser.profiles

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class KMultiProfilesPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "kmulti/profiles").also {
            it.setMethodCallHandler(this)
        }
        binding.platformViewRegistry.registerViewFactory(
            "kmulti/webview",
            KWebViewFactory(binding.binaryMessenger)
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    private fun supported(): Boolean =
        WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "info" -> {
                    val pkg = appContext?.let { WebViewCompat.getCurrentWebViewPackage(it) }
                    val version = if (pkg != null) "${pkg.packageName} ${pkg.versionName}" else "unknown"
                    result.success(mapOf("supported" to supported(), "webViewVersion" to version))
                }
                "ensureProfile" -> {
                    requireSupported()
                    val name = call.argument<String>("name") ?: error("name missing")
                    ProfileStore.getInstance().getOrCreateProfile(name)
                    result.success(null)
                }
                "listProfiles" -> {
                    requireSupported()
                    result.success(ProfileStore.getInstance().allProfileNames)
                }
                "deleteProfile" -> {
                    requireSupported()
                    val name = call.argument<String>("name") ?: error("name missing")
                    // Throws IllegalStateException if a WebView still uses the profile.
                    result.success(ProfileStore.getInstance().deleteProfile(name))
                }
                "share" -> {
                    val text = call.argument<String>("text") ?: error("text missing")
                    val ctx = appContext ?: error("no context")
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    ctx.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "openDownloads" -> {
                    val ctx = appContext ?: error("no context")
                    ctx.startActivity(
                        Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }
                "cookies" -> {
                    requireSupported()
                    val name = call.argument<String>("name") ?: error("name missing")
                    val url = call.argument<String>("url") ?: error("url missing")
                    val profile = ProfileStore.getInstance().getProfile(name)
                    result.success(profile?.cookieManager?.getCookie(url))
                }
                else -> result.notImplemented()
            }
        } catch (e: Throwable) {
            result.error("kmulti_error", e.message ?: e.toString(), null)
        }
    }

    private fun requireSupported() {
        if (!supported()) {
            throw IllegalStateException("WebView Multi-Profile API is not supported on this device")
        }
    }
}
