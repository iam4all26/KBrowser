package com.kainuwa.kmultibrowser.profiles

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.URLUtil
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.TextView
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

/**
 * One WebView permanently bound to one engine profile.
 * If the profile cannot be applied, an error view is shown. There is no fallback
 * to the default (shared) profile. Pop-up windows and downloads also use this profile.
 */
class KWebView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    private val profileName: String
) : PlatformView, MethodChannel.MethodCallHandler {

    private val appContext: Context = context.applicationContext
    private val channel = MethodChannel(messenger, "kmulti/webview_$viewId")
    private var webView: WebView? = null
    private var mobileUa: String = ""
    private val root: View = build(context)

    init {
        channel.setMethodCallHandler(this)
    }

    private fun errorView(context: Context, message: String): View {
        return TextView(context).apply {
            text = message
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#17151F"))
            gravity = Gravity.CENTER
            setPadding(32, 32, 32, 32)
        }
    }

    private fun profileCookies() =
        ProfileStore.getInstance().getProfile(profileName)?.cookieManager

    private fun build(context: Context): View {
        if (profileName.isEmpty()) return errorView(context, "No profile given.")
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
            return errorView(context, "Multi-Profile API not supported. Profile $profileName not opened.")
        }
        return try {
            ProfileStore.getInstance().getOrCreateProfile(profileName)
            val wv = WebView(context)
            // Must happen before any content is loaded.
            WebViewCompat.setProfile(wv, profileName)
            wv.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                useWideViewPort = true
                loadWithOverviewMode = true
                setSupportZoom(true)
                builtInZoomControls = true
                displayZoomControls = false
                setSupportMultipleWindows(true)
                javaScriptCanOpenWindowsAutomatically = true
            }
            mobileUa = wv.settings.userAgentString
            wv.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(
                    view: WebView,
                    request: WebResourceRequest
                ): Boolean {
                    val uri = request.url
                    return when (uri.scheme) {
                        null, "http", "https", "about", "data", "blob", "javascript" -> false
                        else -> openExternal(uri)
                    }
                }

                override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                    notifyPage(view, url)
                }

                override fun onPageFinished(view: WebView, url: String?) {
                    profileCookies()?.flush()
                    notifyPage(view, url)
                }
            }
            wv.webChromeClient = object : WebChromeClient() {
                override fun onProgressChanged(view: WebView, newProgress: Int) {
                    channel.invokeMethod("onProgress", newProgress)
                }

                override fun onReceivedTitle(view: WebView, title: String?) {
                    notifyPage(view, view.url)
                }

                override fun onCreateWindow(
                    view: WebView,
                    isDialog: Boolean,
                    isUserGesture: Boolean,
                    resultMsg: Message
                ): Boolean {
                    // Catch the pop-up URL in a short-lived WebView of the SAME profile
                    // and let Flutter open it as a new tab.
                    val temp = WebView(view.context)
                    try {
                        WebViewCompat.setProfile(temp, profileName)
                    } catch (e: Throwable) {
                        temp.destroy()
                        return false
                    }
                    var fired = false
                    fun fire(url: String?) {
                        if (fired || url.isNullOrEmpty() || url == "about:blank") return
                        fired = true
                        channel.invokeMethod("onNewWindow", url)
                        Handler(Looper.getMainLooper()).post {
                            temp.stopLoading()
                            temp.destroy()
                        }
                    }
                    temp.webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(v: WebView, request: WebResourceRequest): Boolean {
                            fire(request.url.toString())
                            return true
                        }

                        override fun onPageStarted(v: WebView, url: String?, favicon: Bitmap?) {
                            fire(url)
                        }
                    }
                    val transport = resultMsg.obj as WebView.WebViewTransport
                    transport.webView = temp
                    resultMsg.sendToTarget()
                    return true
                }
            }
            wv.setDownloadListener { url, userAgent, contentDisposition, mimeType, _ ->
                startDownload(url, userAgent, contentDisposition, mimeType)
            }
            webView = wv
            wv
        } catch (e: Throwable) {
            errorView(context, "Could not open profile $profileName: ${e.message}")
        }
    }

    private fun openExternal(uri: Uri): Boolean {
        try {
            val intent = if (uri.scheme == "intent") {
                Intent.parseUri(uri.toString(), Intent.URI_INTENT_SCHEME)
            } else {
                Intent(Intent.ACTION_VIEW, uri)
            }
            intent.addCategory(Intent.CATEGORY_BROWSABLE)
            intent.component = null
            intent.selector = null
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            appContext.startActivity(intent)
        } catch (e: Exception) {
            // No app can handle it: block the navigation.
        }
        return true
    }

    private fun startDownload(url: String, userAgent: String?, contentDisposition: String?, mimeType: String?) {
        if (url.startsWith("blob:") || url.startsWith("data:")) {
            channel.invokeMethod("onDownload", mapOf("message" to "This kind of download is not supported yet"))
            return
        }
        try {
            val name = URLUtil.guessFileName(url, contentDisposition, mimeType)
            val request = DownloadManager.Request(Uri.parse(url))
            if (!mimeType.isNullOrEmpty()) request.setMimeType(mimeType)
            // Use THIS profile's cookies so logged-in downloads work and stay profile-bound.
            val cookie = profileCookies()?.getCookie(url)
            if (!cookie.isNullOrEmpty()) request.addRequestHeader("Cookie", cookie)
            if (!userAgent.isNullOrEmpty()) request.addRequestHeader("User-Agent", userAgent)
            request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name)
            val dm = appContext.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            dm.enqueue(request)
            channel.invokeMethod("onDownload", mapOf("message" to "Downloading $name"))
        } catch (e: Throwable) {
            channel.invokeMethod("onDownload", mapOf("message" to "Download failed: ${e.message}"))
        }
    }

    private fun desktopUa(ua: String): String =
        ua.replace(Regex("\\(Linux; Android[^)]*\\)"), "(X11; Linux x86_64)")
            .replace(" Mobile", "")
            .replace("Version/4.0 ", "")

    private fun notifyPage(view: WebView, url: String?) {
        channel.invokeMethod(
            "onPage",
            mapOf(
                "url" to (url ?: view.url ?: ""),
                "title" to (view.title ?: ""),
                "canGoBack" to view.canGoBack(),
                "canGoForward" to view.canGoForward()
            )
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val wv = webView
        if (wv == null) {
            result.error("no_webview", "WebView not available for $profileName", null)
            return
        }
        when (call.method) {
            "loadUrl" -> {
                val url = call.argument<String>("url")
                if (url == null) result.error("bad_args", "url missing", null)
                else { wv.loadUrl(url); result.success(null) }
            }
            "loadTestPage" -> {
                wv.loadDataWithBaseURL(TEST_BASE_URL, TEST_HTML, "text/html", "utf-8", null)
                result.success(null)
            }
            "reload" -> { wv.reload(); result.success(null) }
            "stop" -> { wv.stopLoading(); result.success(null) }
            "goBack" -> { if (wv.canGoBack()) wv.goBack(); result.success(null) }
            "goForward" -> { if (wv.canGoForward()) wv.goForward(); result.success(null) }
            "setDesktopMode" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val reload = call.argument<Boolean>("reload") ?: true
                wv.settings.userAgentString = if (enabled) desktopUa(mobileUa) else mobileUa
                if (reload && wv.url != null) wv.reload()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun getView(): View = root

    override fun dispose() {
        channel.setMethodCallHandler(null)
        try {
            profileCookies()?.flush()
        } catch (e: Throwable) {
        }
        webView?.let {
            (it.parent as? ViewGroup)?.removeView(it)
            it.destroy()
        }
        webView = null
    }

    companion object {
        const val TEST_BASE_URL = "https://kmulti.test/"

        private const val TEST_HTML = """<!doctype html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body{font-family:sans-serif;background:#17151F;color:#fff;padding:16px}
input,button{font-size:16px;padding:10px;margin:4px 0;width:100%;box-sizing:border-box}
button{background:#7351FF;color:#fff;border:0;border-radius:6px}
pre{background:#000;padding:10px;border-radius:6px;white-space:pre-wrap}
</style></head><body>
<h3>Isolation test page</h3>
<p>Type a name, tap Save login, then switch profile and compare.</p>
<input id="u" placeholder="Name to log in as">
<button onclick="save()">Save login</button>
<button onclick="clr()">Log out</button>
<pre id="out"></pre>
<script>
function getCookie(){
  var m=document.cookie.match(/(?:^|; )kmulti_user=([^;]*)/);
  return m?decodeURIComponent(m[1]):null;
}
function show(){
  var ls=null;
  try{ls=localStorage.getItem('kmulti_user');}catch(e){ls='error: '+e;}
  document.getElementById('out').textContent=
    'Cookie user: '+getCookie()+'\nlocalStorage user: '+ls;
}
function save(){
  var v=document.getElementById('u').value||'(empty)';
  document.cookie='kmulti_user='+encodeURIComponent(v)+'; path=/; max-age=31536000; Secure; SameSite=Lax';
  try{localStorage.setItem('kmulti_user',v);}catch(e){}
  show();
}
function clr(){
  document.cookie='kmulti_user=; path=/; max-age=0; Secure; SameSite=Lax';
  try{localStorage.removeItem('kmulti_user');}catch(e){}
  show();
}
show();
</script></body></html>"""
    }
}
