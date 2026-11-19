package com.kainuwa.kmultibrowser.profiles

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.media.MediaScannerConnection
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
import android.webkit.URLUtil
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.util.Base64
import android.webkit.HttpAuthHandler
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.TextView
import androidx.webkit.ProfileStore
import androidx.webkit.ScriptHandler
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.net.Authenticator
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.PasswordAuthentication
import java.net.Proxy
import java.net.URL
import java.util.concurrent.atomic.AtomicInteger
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
    private val scriptHandlers = mutableListOf<ScriptHandler>()
    @Volatile private var adBlock = false
    private val blockedCount = AtomicInteger(0)
    private val proxyAuthAttempts = AtomicInteger(0)
    private val mainHandler = Handler(Looper.getMainLooper())
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

                override fun onReceivedHttpAuthRequest(
                    view: WebView,
                    handler: HttpAuthHandler,
                    host: String?,
                    realm: String?
                ) {
                    // Login asked by the proxy server: answer with the proxy login (a few tries only).
                    if (ProxyState.active && ProxyState.username.isNotEmpty() &&
                        host != null && host.equals(ProxyState.host, ignoreCase = true)
                    ) {
                        if (proxyAuthAttempts.incrementAndGet() <= 3) {
                            handler.proceed(ProxyState.username, ProxyState.password)
                        } else {
                            handler.cancel()
                        }
                        return
                    }
                    super.onReceivedHttpAuthRequest(view, handler, host, realm)
                }

                override fun shouldInterceptRequest(
                    view: WebView,
                    request: WebResourceRequest
                ): WebResourceResponse? {
                    if (adBlock && !request.isForMainFrame && AdBlockList.isBlocked(request.url.host)) {
                        blockedCount.incrementAndGet()
                        return WebResourceResponse(
                            "text/plain", "utf-8", 403, "Blocked",
                            emptyMap(), ByteArrayInputStream(ByteArray(0))
                        )
                    }
                    return super.shouldInterceptRequest(view, request)
                }

                override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                    blockedCount.set(0)
                    proxyAuthAttempts.set(0)
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
        if (ProxyState.active && ProxyState.scheme == "https") {
            say("Downloads are not available through an HTTPS proxy yet")
            return
        }
        val cookie = profileCookies()?.getCookie(url)
        val referer = webView?.url
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // Android 9 and below need the storage permission to save into the public Downloads folder.
            permissions.request(listOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)) {
                runDownload(url, userAgent, contentDisposition, mimeType, cookie, referer)
            }
        } else {
            runDownload(url, userAgent, contentDisposition, mimeType, cookie, referer)
        }
    }

    private fun runDownload(
        url: String,
        userAgent: String?,
        contentDisposition: String?,
        mimeType: String?,
        cookie: String?,
        referer: String?
    ) {
        say("Downloading...")
        thread(name = "kmulti-download") {
            // Older Android versions (for example Android 8) can fail with "unexpected end of
            // stream" when a server or a mobile network closes a connection without a reply.
            // So: no connection reuse, no compression, and up to 3 tries on fresh connections.
            val attempts = 3
            var lastError: Throwable? = null
            for (attempt in 1..attempts) {
                var conn: HttpURLConnection? = null
                try {
                    conn = openUrlConnection(url).apply {
                        connectTimeout = 20000
                        readTimeout = 30000
                        instanceFollowRedirects = true
                        useCaches = false
                        setRequestProperty("Connection", "close")
                        setRequestProperty("Accept-Encoding", "identity")
                        setRequestProperty("Accept", "*/*")
                        if (!cookie.isNullOrEmpty()) setRequestProperty("Cookie", cookie)
                        if (!userAgent.isNullOrEmpty()) setRequestProperty("User-Agent", userAgent)
                        // The last try leaves the Referer out (some servers drop such requests).
                        if (attempt < attempts && !referer.isNullOrEmpty()) setRequestProperty("Referer", referer)
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
                    say(
                        if (saved.publicFolder) "Saved to Downloads: ${saved.name}"
                        else "Saved in the app's own folder (storage permission was not allowed): ${saved.name}"
                    )
                    mainHandler.post {
                        try {
                            channel.invokeMethod(
                                "onDownloadDone",
                                mapOf(
                                    "name" to saved.name,
                                    "location" to saved.location,
                                    "isUri" to saved.isUri,
                                    "mime" to mime,
                                    "size" to saved.size,
                                    "sourceUrl" to url
                                )
                            )
                        } catch (e: Throwable) {
                        }
                    }
                    return@thread
                } catch (e: IOException) {
                    lastError = e
                    if (attempt < attempts) {
                        try {
                            Thread.sleep(700L * attempt)
                        } catch (_: InterruptedException) {
                        }
                    }
                } catch (e: Throwable) {
                    lastError = e
                    break
                } finally {
                    conn?.disconnect()
                }
            }
            val host = try { URL(url).host } catch (_: Throwable) { "?" }
            val via = if (ProxyState.active) "proxy on" else "no proxy"
            say("Download failed ($host, $via, Android ${Build.VERSION.RELEASE}): ${lastError?.javaClass?.simpleName}: ${lastError?.message}")
        }
    }

    /** Opens the download connection through the profile's proxy when one is on. */
    private fun openUrlConnection(url: String): HttpURLConnection {
        if (!ProxyState.active) return URL(url).openConnection() as HttpURLConnection
        val type = if (ProxyState.scheme == "socks5") Proxy.Type.SOCKS else Proxy.Type.HTTP
        val proxy = Proxy(type, InetSocketAddress.createUnresolved(ProxyState.host, ProxyState.port))
        val user = ProxyState.username
        val pass = ProxyState.password
        if (user.isNotEmpty()) {
            Authenticator.setDefault(object : Authenticator() {
                override fun getPasswordAuthentication(): PasswordAuthentication? =
                    if (requestorType == Authenticator.RequestorType.PROXY) {
                        PasswordAuthentication(user, pass.toCharArray())
                    } else null
            })
        }
        val conn = URL(url).openConnection(proxy) as HttpURLConnection
        if (user.isNotEmpty() && type == Proxy.Type.HTTP) {
            val token = Base64.encodeToString("$user:$pass".toByteArray(), Base64.NO_WRAP)
            conn.setRequestProperty("Proxy-Authorization", "Basic $token")
        }
        return conn
    }

    private class Saved(
        val name: String,
        val location: String,
        val isUri: Boolean,
        val publicFolder: Boolean,
        val size: Long
    )

    private fun saveToDownloads(name: String, mime: String, input: InputStream): Saved {
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
            var size = 0L
            try {
                val out = resolver.openOutputStream(uri) ?: throw IOException("Could not open the file")
                size = out.use { input.copyTo(it) }
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
            return Saved(finalName ?: name, uri.toString(), true, true, size)
        }
        // Android 9 and below: the public Downloads folder needs the storage permission.
        // If it was refused, fall back to the app's own folder (and say so).
        var dir: File = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        var publicFolder = true
        if (!(dir.exists() || dir.mkdirs()) || !dir.canWrite()) {
            publicFolder = false
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
        val size = try {
            target.outputStream().use { input.copyTo(it) }
        } catch (e: Throwable) {
            // Do not leave a half-written file behind (a retry would create "name (1).pdf").
            try {
                target.delete()
            } catch (_: Throwable) {
            }
            throw e
        }
        if (publicFolder) {
            try {
                MediaScannerConnection.scanFile(appContext, arrayOf(target.absolutePath), arrayOf(mime), null)
            } catch (_: Throwable) {
            }
        }
        return Saved(target.name, target.absolutePath, false, publicFolder, size)
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
                "finished" to finished,
                "blocked" to blockedCount.get()
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
            "captureThumbnail" -> {
                val w = wv.width
                val h = wv.height
                if (w <= 0 || h <= 0) {
                    result.success(null)
                    return
                }
                try {
                    val targetW = 360
                    val scale = targetW.toFloat() / w
                    val th = (h * scale).toInt().coerceAtLeast(1)
                    val bmp = Bitmap.createBitmap(targetW, th, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(bmp)
                    canvas.scale(scale, scale)
                    wv.draw(canvas)
                    val out = ByteArrayOutputStream()
                    bmp.compress(Bitmap.CompressFormat.JPEG, 70, out)
                    bmp.recycle()
                    result.success(out.toByteArray())
                } catch (e: Throwable) {
                    result.success(null)
                }
            }
            "setAdBlock" -> {
                adBlock = call.argument<Boolean>("enabled") ?: false
                result.success(null)
            }
            "setExtensions" -> {
                val scripts = call.argument<List<String>>("scripts") ?: emptyList()
                for (h in scriptHandlers) {
                    try { h.remove() } catch (e: Throwable) { }
                }
                scriptHandlers.clear()
                if (scripts.isNotEmpty()) {
                    if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                        result.error("unsupported", "This WebView version cannot run extensions", null)
                        return
                    }
                    try {
                        for (s in scripts) {
                            scriptHandlers.add(WebViewCompat.addDocumentStartJavaScript(wv, s, setOf("*")))
                        }
                    } catch (e: Throwable) {
                        result.error("extension_error", e.message ?: e.toString(), null)
                        return
                    }
                }
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
