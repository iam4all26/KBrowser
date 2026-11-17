package com.kainuwa.kmultibrowser.profiles

import android.Manifest
import android.app.AlertDialog
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.provider.MediaStore
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.GeolocationPermissions
import android.webkit.PermissionRequest
import android.webkit.URLUtil
import android.webkit.ValueCallback
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
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * One WebView permanently bound to one engine profile.
 * If the profile cannot be applied, an error view is shown. There is no fallback
 * to the default (shared) profile. Pop-up windows and downloads also use this profile.
 */
class KWebView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    private val profileName: String,
    private val fileChooser: FileChooserBridge,
    private val permissions: PermissionBridge
) : PlatformView, MethodChannel.MethodCallHandler {

    private val appContext: Context = context.applicationContext
    private val channel = MethodChannel(messenger, "kmulti/webview_$viewId")
    private var webView: WebView? = null
    private var mobileUa: String = ""
    private var desktop: Boolean = false
    private val mainHandler = Handler(Looper.getMainLooper())
    // Site decisions live as long as this WebView (one tab), never saved to disk.
    private val siteDecisions = HashMap<String, Boolean>()
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

                override fun onPageCommitVisible(view: WebView, url: String?) {
                    applyDesktopViewport(view)
                }

                override fun onPageFinished(view: WebView, url: String?) {
                    profileCookies()?.flush()
                    applyDesktopViewport(view)
                    notifyPage(view, url, true)
                }
            }
            wv.webChromeClient = object : WebChromeClient() {
                override fun onProgressChanged(view: WebView, newProgress: Int) {
                    channel.invokeMethod("onProgress", newProgress)
                }

                override fun onReceivedTitle(view: WebView, title: String?) {
                    notifyPage(view, view.url)
                }

                override fun onPermissionRequest(request: PermissionRequest) {
                    val wantVideo = request.resources.contains(PermissionRequest.RESOURCE_VIDEO_CAPTURE)
                    val wantAudio = request.resources.contains(PermissionRequest.RESOURCE_AUDIO_CAPTURE)
                    if (!wantVideo && !wantAudio) {
                        request.deny()
                        return
                    }
                    val origin = request.origin.toString()
                    val what = when {
                        wantVideo && wantAudio -> "your camera and microphone"
                        wantVideo -> "your camera"
                        else -> "your microphone"
                    }
                    askSite("media:$wantVideo:$wantAudio:$origin", origin, what) { allowed ->
                        if (!allowed) {
                            request.deny()
                            return@askSite
                        }
                        val perms = ArrayList<String>()
                        if (wantVideo) perms.add(Manifest.permission.CAMERA)
                        if (wantAudio) perms.add(Manifest.permission.RECORD_AUDIO)
                        permissions.request(perms) { res ->
                            val grant = ArrayList<String>()
                            if (wantVideo && res[Manifest.permission.CAMERA] == true) {
                                grant.add(PermissionRequest.RESOURCE_VIDEO_CAPTURE)
                            }
                            if (wantAudio && res[Manifest.permission.RECORD_AUDIO] == true) {
                                grant.add(PermissionRequest.RESOURCE_AUDIO_CAPTURE)
                            }
                            if (grant.isEmpty()) request.deny() else request.grant(grant.toTypedArray())
                        }
                    }
                }

                override fun onGeolocationPermissionsShowPrompt(
                    origin: String,
                    callback: GeolocationPermissions.Callback
                ) {
                    askSite("location:$origin", origin, "your location") { allowed ->
                        if (!allowed) {
                            callback.invoke(origin, false, false)
                            return@askSite
                        }
                        permissions.request(
                            listOf(
                                Manifest.permission.ACCESS_FINE_LOCATION,
                                Manifest.permission.ACCESS_COARSE_LOCATION
                            )
                        ) { res ->
                            callback.invoke(origin, res.values.any { it }, false)
                        }
                    }
                }

                override fun onShowFileChooser(
                    webView: WebView,
                    filePathCallback: ValueCallback<Array<Uri>>,
                    fileChooserParams: WebChromeClient.FileChooserParams
                ): Boolean = fileChooser.launch(fileChooserParams, filePathCallback)

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
            wv.setFindListener { activeOrdinal, numberOfMatches, isDoneCounting ->
                channel.invokeMethod(
                    "onFind",
                    mapOf(
                        "active" to activeOrdinal,
                        "total" to numberOfMatches,
                        "done" to isDoneCounting
                    )
                )
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

    /**
     * Asks the person whether [origin] may use [what]. Allow and Block are
     * remembered for this tab only; dismissing the dialog counts as "not now".
     */
    private fun askSite(key: String, origin: String, what: String, done: (Boolean) -> Unit) {
        siteDecisions[key]?.let {
            done(it)
            return
        }
        val act = permissions.activity
        if (act == null) {
            done(false)
            return
        }
        val host = try {
            Uri.parse(origin).host ?: origin
        } catch (e: Throwable) {
            origin
        }
        try {
            AlertDialog.Builder(act)
                .setTitle("Allow $host?")
                .setMessage("$host wants to use $what.")
                .setPositiveButton("Allow") { _, _ ->
                    siteDecisions[key] = true
                    done(true)
                }
                .setNegativeButton("Block") { _, _ ->
                    siteDecisions[key] = false
                    done(false)
                }
                .setOnCancelListener { done(false) }
                .show()
        } catch (e: Throwable) {
            done(false)
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

    private fun say(msg: String) {
        mainHandler.post {
            try {
                channel.invokeMethod("onDownload", mapOf("message" to msg))
            } catch (e: Throwable) {
            }
        }
    }

    /**
     * Own downloader (does not use the Android DownloadManager). Uses THIS profile's
     * cookies and saves into the public Downloads folder.
     */
    private fun startDownload(url: String, userAgent: String?, contentDisposition: String?, mimeType: String?) {
        if (url.startsWith("blob:") || url.startsWith("data:")) {
            say("This kind of download is not supported yet")
            return
        }
        val cookie = profileCookies()?.getCookie(url)
        val referer = webView?.url
        say("Downloading...")
        thread(name = "kmulti-download") {
            var conn: HttpURLConnection? = null
            try {
                conn = (URL(url).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 20000
                    readTimeout = 30000
                    instanceFollowRedirects = true
                    if (!cookie.isNullOrEmpty()) setRequestProperty("Cookie", cookie)
                    if (!userAgent.isNullOrEmpty()) setRequestProperty("User-Agent", userAgent)
                    if (!referer.isNullOrEmpty()) setRequestProperty("Referer", referer)
                }
                val code = conn.responseCode
                if (code !in 200..299) {
                    say("Download failed: HTTP $code")
                    return@thread
                }
                val cd = conn.getHeaderField("Content-Disposition") ?: contentDisposition
                val headerMime = conn.contentType?.substringBefore(';')?.trim()
                val mime = if (!headerMime.isNullOrEmpty()) headerMime
                else if (!mimeType.isNullOrEmpty()) mimeType
                else "application/octet-stream"
                val name = URLUtil.guessFileName(url, cd, mime)
                val saved = conn.inputStream.use { saveToDownloads(name, mime, it) }
                say("Saved to Downloads: $saved")
            } catch (e: Throwable) {
                say("Download failed: ${e.message}")
            } finally {
                conn?.disconnect()
            }
        }
    }

    private fun saveToDownloads(name: String, mime: String, input: InputStream): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = appContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("Could not create the file")
            try {
                val out = resolver.openOutputStream(uri) ?: throw IOException("Could not open the file")
                out.use { input.copyTo(it) }
                val done = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
                resolver.update(uri, done, null, null)
            } catch (e: Throwable) {
                try {
                    resolver.delete(uri, null, null)
                } catch (_: Throwable) {
                }
                throw e
            }
            val finalName = resolver.query(
                uri, arrayOf(MediaStore.Downloads.DISPLAY_NAME), null, null, null
            )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
            return finalName ?: name
        }
        // Android 9 and below: public Downloads needs the storage permission, so
        // fall back to the app's own downloads folder if it is refused.
        var dir: File = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!(dir.exists() || dir.mkdirs()) || !dir.canWrite()) {
            dir = appContext.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: appContext.filesDir
            dir.mkdirs()
        }
        var target = File(dir, name)
        var i = 1
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        while (target.exists()) {
            target = File(dir, "$base ($i)$ext")
            i++
        }
        target.outputStream().use { input.copyTo(it) }
        return target.name
    }

    private fun applyDesktopViewport(view: WebView) {
        if (!desktop) return
        view.evaluateJavascript(DESKTOP_JS, null)
    }

    private fun desktopUa(ua: String): String =
        ua.replace(Regex("\\(Linux; Android[^)]*\\)"), "(X11; Linux x86_64)")
            .replace(" Mobile", "")
            .replace("Version/4.0 ", "")

    private fun notifyPage(view: WebView, url: String?, finished: Boolean = false) {
        channel.invokeMethod(
            "onPage",
            mapOf(
                "url" to (url ?: view.url ?: ""),
                "title" to (view.title ?: ""),
                "canGoBack" to view.canGoBack(),
                "canGoForward" to view.canGoForward(),
                "finished" to finished
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
                desktop = enabled
                wv.settings.userAgentString = if (enabled) desktopUa(mobileUa) else mobileUa
                if (reload && wv.url != null) wv.reload()
                result.success(null)
            }
            "find" -> {
                val q = call.argument<String>("query") ?: ""
                if (q.isEmpty()) wv.clearMatches() else wv.findAllAsync(q)
                result.success(null)
            }
            "findNext" -> {
                wv.findNext(call.argument<Boolean>("forward") ?: true)
                result.success(null)
            }
            "clearFind" -> { wv.clearMatches(); result.success(null) }
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

        private const val DESKTOP_JS =
            "(function(){var m=document.querySelector('meta[name=viewport]');" +
            "if(!m){m=document.createElement('meta');m.name='viewport';" +
            "(document.head||document.documentElement).appendChild(m);}" +
            "m.setAttribute('content','width=1024');})();"

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
