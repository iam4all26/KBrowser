package com.kainuwa.kmultibrowser.profiles

import android.app.DownloadManager
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.net.Uri
import androidx.webkit.ProfileStore
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executor

class KMultiProfilesPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private val fileChooser = FileChooserBridge()
    private val permissions = PermissionBridge()
    private var activityBinding: ActivityPluginBinding? = null
    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "kmulti/profiles").also {
            it.setMethodCallHandler(this)
        }
        binding.platformViewRegistry.registerViewFactory(
            "kmulti/webview",
            KWebViewFactory(binding.binaryMessenger, fileChooser, permissions)
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding?.removeActivityResultListener(fileChooser)
        activityBinding?.removeRequestPermissionsResultListener(permissions)
        activityBinding = binding
        fileChooser.activity = binding.activity
        permissions.activity = binding.activity
        binding.addActivityResultListener(fileChooser)
        binding.addRequestPermissionsResultListener(permissions)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(fileChooser)
        activityBinding?.removeRequestPermissionsResultListener(permissions)
        activityBinding = null
        fileChooser.activity = null
        permissions.activity = null
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
                "setProxy" -> {
                    if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
                        result.error("unsupported", "This WebView cannot use a proxy", null)
                        return
                    }
                    val executor = Executor { r -> mainHandler.post(r) }
                    if (call.argument<Boolean>("clear") == true) {
                        ProxyState.clear()
                        ProxyController.getInstance().clearProxyOverride(executor, Runnable { result.success(null) })
                        return
                    }
                    val scheme = call.argument<String>("scheme") ?: error("scheme missing")
                    val host = call.argument<String>("host") ?: error("host missing")
                    val port = call.argument<Int>("port") ?: error("port missing")
                    if (scheme != "http" && scheme != "https" && scheme != "socks5") error("unsupported proxy type")
                    // No direct fallback: if the proxy fails, pages fail instead of using the real IP.
                    val config = ProxyConfig.Builder().addProxyRule("$scheme://$host:$port").build()
                    ProxyState.set(
                        scheme, host, port,
                        call.argument<String>("username") ?: "",
                        call.argument<String>("password") ?: ""
                    )
                    // Result is sent only when WebView confirms the new proxy is in use.
                    ProxyController.getInstance().setProxyOverride(config, executor, Runnable { result.success(null) })
                }
                "proxyGeo" -> {
                    // mode "current": the proxy in use. "direct": the phone's own connection
                    // (refused while a proxy is applied). "via": one given proxy.
                    val mode = call.argument<String>("mode") ?: "current"
                    val vScheme = call.argument<String>("scheme") ?: ""
                    val vHost = call.argument<String>("host") ?: ""
                    val vPort = call.argument<Int>("port") ?: 0
                    val vUser = call.argument<String>("username") ?: ""
                    val vPass = call.argument<String>("password") ?: ""
                    Thread {
                        val r = try {
                            when (mode) {
                                "direct" -> GeoLookup.lookupDirect()
                                "via" -> GeoLookup.lookupVia(vScheme, vHost, vPort, vUser, vPass)
                                else -> GeoLookup.lookup()
                            }
                        } catch (e: Throwable) { null }
                        mainHandler.post { result.success(r) }
                    }.start()
                }
                "clearSiteData" -> {
                    requireSupported()
                    val name = call.argument<String>("name") ?: error("name missing")
                    val profile = ProfileStore.getInstance().getProfile(name) ?: error("profile not found")
                    if (call.argument<Boolean>("cookies") == true) {
                        profile.cookieManager.removeAllCookies(null)
                        profile.cookieManager.flush()
                    }
                    if (call.argument<Boolean>("storage") == true) {
                        profile.webStorage.deleteAllData()
                    }
                    result.success(null)
                }
                "encrypt" -> {
                    val text = call.argument<String>("text") ?: error("text missing")
                    result.success(KeystoreCrypto.encrypt(text))
                }
                "decrypt" -> {
                    val text = call.argument<String>("text") ?: error("text missing")
                    result.success(KeystoreCrypto.decrypt(text))
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
                    // The system Downloads app can be broken on some devices, so try the
                    // file manager's Download folder first.
                    val attempts = listOf(
                        Intent(Intent.ACTION_VIEW).setDataAndType(
                            Uri.parse("content://com.android.externalstorage.documents/document/primary%3ADownload"),
                            "vnd.android.document/directory"
                        ),
                        Intent(DownloadManager.ACTION_VIEW_DOWNLOADS)
                    )
                    var opened = false
                    for (i in attempts) {
                        try {
                            ctx.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            opened = true
                            break
                        } catch (e: Exception) {
                        }
                    }
                    if (!opened) error("No app can show Downloads")
                    result.success(null)
                }
                "openFile", "shareFile" -> {
                    val ctx = appContext ?: error("no context")
                    val loc = call.argument<String>("location") ?: error("location missing")
                    val isUri = call.argument<Boolean>("isUri") ?: false
                    val mime = call.argument<String>("mime")?.takeIf { it.isNotEmpty() } ?: "*/*"
                    val uri = if (isUri) Uri.parse(loc)
                    else FileProvider.getUriForFile(ctx, "${ctx.packageName}.kmultifileprovider", File(loc))
                    if (call.method == "openFile") {
                        val view = Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, mime)
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        try {
                            ctx.startActivity(view)
                        } catch (e: Exception) {
                            error("No app can open this file")
                        }
                    } else {
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = mime
                            putExtra(Intent.EXTRA_STREAM, uri)
                            clipData = ClipData.newRawUri("", uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        ctx.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }
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
