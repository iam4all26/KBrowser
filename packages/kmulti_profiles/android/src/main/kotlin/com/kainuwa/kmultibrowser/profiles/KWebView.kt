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
import android.webkit.JavascriptInterface
import android.webkit.URLUtil
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.util.Base64
import android.webkit.HttpAuthHandler
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.webkit.ProfileStore
import androidx.webkit.ScriptHandler
import androidx.webkit.WebSettingsCompat
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
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import okhttp3.ConnectionPool
import okhttp3.Credentials
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
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
    private var container: FrameLayout? = null
    private var popup: View? = null
    private var popupWebView: WebView? = null
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
            // Batch 23: Google sign-in. Google rejects embedded WebViews ("disallowed_useragent")
            // by looking for "; wv)" and "Version/4.0" in the User-Agent and for the
            // X-Requested-With header. Present a normal Chrome-style mobile UA instead.
            // Batch 25: login capture bridge. Page code can only call save() and formSeen();
            // the site address always comes from the WebView itself, never from the page.
            wv.addJavascriptInterface(PwBridge(), "KMultiPw")
            mobileUa = chromeStyleUa(wv.settings.userAgentString)
            wv.settings.userAgentString = mobileUa
            try {
                if (WebViewFeature.isFeatureSupported(WebViewFeature.REQUESTED_WITH_HEADER_ALLOW_LIST)) {
                    WebSettingsCompat.setRequestedWithHeaderOriginAllowList(wv.settings, emptySet())
                }
            } catch (e: Throwable) { }
            // "Sign in with Google" buttons and accounts.google.com need third-party cookies.
            // The cookie manager is the profile's own, so nothing is shared between profiles.
            try { profileCookies()?.setAcceptThirdPartyCookies(wv, true) } catch (e: Throwable) { }
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
                    fun fire(url: String?, fromOverride: Boolean) {
                        if (fired || url.isNullOrEmpty() || url == "about:blank") return
                        fired = true
                        // Batch 23c: login/OAuth/payment pop-ups must stay linked to the page that
                        // opened them (window.opener), so they are kept as a real pop-up
                        // overlay instead of being turned into a separate tab.
                        if (isAuthPopup(url, isDialog)) {
                            mainHandler.post { promotePopup(temp, view, url, fromOverride) }
                            return
                        }
                        channel.invokeMethod("onNewWindow", url)
                        Handler(Looper.getMainLooper()).post {
                            temp.stopLoading()
                            temp.destroy()
                        }
                    }
                    temp.webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(v: WebView, request: WebResourceRequest): Boolean {
                            fire(request.url.toString(), true)
                            return true
                        }

                        override fun onPageStarted(v: WebView, url: String?, favicon: Bitmap?) {
                            fire(url, false)
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
            val frame = FrameLayout(context)
            frame.addView(wv, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            container = frame
            frame
        } catch (e: Throwable) {
            errorView(context, "Could not open profile $profileName: ${e.message}")
        }
    }

    /**
     * True for pop-ups that must keep window.opener (login, OAuth, payment windows).
     * window.open with size features (isDialog) is how almost all of them are opened.
     * Otherwise known identity hosts and OAuth-style URLs. Plain links open as tabs.
     */
    private inner class PwBridge {
        @JavascriptInterface
        fun save(user: String?, pass: String?) {
            val u = (user ?: "").take(256)
            val p = (pass ?: "").take(512)
            if (p.isEmpty()) return
            mainHandler.post {
                try {
                    channel.invokeMethod(
                        "onLoginSubmitted",
                        mapOf("url" to (webView?.url ?: ""), "username" to u, "password" to p)
                    )
                } catch (e: Throwable) { }
            }
        }

        @JavascriptInterface
        fun formSeen() {
            mainHandler.post {
                try { channel.invokeMethod("onLoginForm", webView?.url ?: "") } catch (e: Throwable) { }
            }
        }
    }

    /** Puts a saved login into the visible login form of the page (user tapped Fill). */
    private fun fillJs(user: String, pass: String): String {
        val u = org.json.JSONObject.quote(user)
        val p = org.json.JSONObject.quote(pass)
        return "(function(u,p){try{" +
            "function vis(e){var r=e.getBoundingClientRect();var s=getComputedStyle(e);" +
            "return r.width>0&&r.height>0&&s.visibility!=='hidden'&&s.display!=='none';}" +
            "function setv(e,v){var d=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value');" +
            "d.set.call(e,v);e.dispatchEvent(new Event('input',{bubbles:true}));" +
            "e.dispatchEvent(new Event('change',{bubbles:true}));}" +
            "var pws=[].slice.call(document.querySelectorAll('input[type=password]')).filter(vis);" +
            "if(!pws.length)return;var pw=pws[0];var scope=pw.form||document;var user=null;" +
            "[].slice.call(scope.querySelectorAll('input')).forEach(function(e){" +
            "var t=(e.type||'text').toLowerCase();" +
            "if(e!==pw&&vis(e)&&!e.disabled&&!e.readOnly&&(t==='text'||t==='email'||t==='tel')" +
            "&&(e.compareDocumentPosition(pw)&Node.DOCUMENT_POSITION_FOLLOWING))user=e;});" +
            "if(user&&u)setv(user,u);setv(pw,p);}catch(x){}})($u,$p);"
    }

    private fun isAuthPopup(url: String, isDialog: Boolean): Boolean {
        if (isDialog) return true
        val host = try { (Uri.parse(url).host ?: "").lowercase() } catch (e: Throwable) { return false }
        if (host == "accounts.google.com" || host == "appleid.apple.com" ||
            host == "login.microsoftonline.com" || host == "login.live.com" ||
            host == "api.twitter.com" || host.endsWith(".okta.com") ||
            host.endsWith(".auth0.com") || host.endsWith(".b2clogin.com")
        ) return true
        val l = url.lowercase()
        val markers = listOf(
            "/oauth", "oauth2", "/authorize", "/dialog/", "openid",
            "response_type=", "client_id=", "redirect_uri=", "/saml"
        )
        return markers.any { l.contains(it) }
    }

    private fun closePopup() {
        val v = popup
        val w = popupWebView
        popup = null
        popupWebView = null
        if (v != null) (v.parent as? ViewGroup)?.removeView(v)
        if (w != null) {
            try { w.stopLoading() } catch (e: Throwable) { }
            try { w.destroy() } catch (e: Throwable) { }
        }
    }

    /** Shows the pop-up WebView (same profile, still linked to its opener) over the page. */
    private fun promotePopup(pop: WebView, opener: WebView, url: String, reload: Boolean) {
        val frame = container
        if (frame == null) {
            pop.destroy()
            return
        }
        closePopup()
        pop.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            javaScriptCanOpenWindowsAutomatically = true
            userAgentString = opener.settings.userAgentString
        }
        try {
            if (WebViewFeature.isFeatureSupported(WebViewFeature.REQUESTED_WITH_HEADER_ALLOW_LIST)) {
                WebSettingsCompat.setRequestedWithHeaderOriginAllowList(pop.settings, emptySet())
            }
        } catch (e: Throwable) { }
        try { profileCookies()?.setAcceptThirdPartyCookies(pop, true) } catch (e: Throwable) { }
        pop.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(v: WebView, request: WebResourceRequest): Boolean =
                when (request.url.scheme) {
                    null, "http", "https", "about", "data", "blob", "javascript" -> false
                    else -> true
                }
        }
        pop.webChromeClient = object : WebChromeClient() {
            override fun onCloseWindow(window: WebView) {
                mainHandler.post { closePopup() }
            }
        }
        val density = frame.context.resources.displayMetrics.density
        val bar = LinearLayout(frame.context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Color.parseColor("#17151F"))
            setPadding((12 * density).toInt(), 0, (12 * density).toInt(), 0)
        }
        bar.addView(TextView(frame.context).apply {
            text = "Sign in"
            setTextColor(Color.WHITE)
            textSize = 15f
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        bar.addView(TextView(frame.context).apply {
            text = "Close"
            setTextColor(Color.parseColor("#F6C101"))
            textSize = 15f
            setPadding((12 * density).toInt(), (12 * density).toInt(), 0, (12 * density).toInt())
            setOnClickListener { closePopup() }
        })
        val column = LinearLayout(frame.context).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.WHITE)
            isClickable = true
        }
        column.addView(bar, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, (44 * density).toInt()))
        column.addView(pop, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        frame.addView(column, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        popup = column
        popupWebView = pop
        if (reload) pop.loadUrl(url)
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
        val dlId = "d${downloadSeq.incrementAndGet()}_${System.currentTimeMillis()}"
        // Shown in the Downloads screen straight away, with a name guessed from the address.
        val firstName = fileNameFor(url, contentDisposition, mimeType)
        sendDl("onDownloadStart", mapOf("id" to dlId, "name" to firstName, "sourceUrl" to url))
        thread(name = "kmulti-download") {
            // OkHttp is used instead of HttpURLConnection: the built-in one on older Android
            // versions (for example Android 8) breaks on authenticated HTTPS proxies and on
            // connections that a server or mobile network closes early. Up to 3 tries, each on
            // a fresh connection.
            val attempts = 3
            var lastError: Throwable? = null
            var httpFail: String? = null
            val client = buildDownloadClient()
            for (attempt in 1..attempts) {
                try {
                    val req = Request.Builder().url(url)
                        .header("Connection", "close")
                        .apply { browserHeaders(this, attempt, attempts, url, userAgent, referer) }
                        .apply { if (!cookie.isNullOrEmpty()) header("Cookie", cookie) }
                        .build()
                    client.newCall(req).execute().use { resp ->
                        if (!resp.isSuccessful) {
                            val server = resp.header("Server").orEmpty()
                            val who = when {
                                resp.header("CF-Ray") != null || server.contains("cloudflare", true) -> " (Cloudflare)"
                                server.isNotEmpty() -> " ($server)"
                                else -> ""
                            }
                            val msg = "Download failed: HTTP ${resp.code}$who" +
                                (if (ProxyState.active) ", via proxy" else ", no proxy") +
                                (if (attempt > 1) ", try $attempt of $attempts" else "")
                            // Sites that guard against bots answer 403, 429 or 503 to a request that
                            // does not look like Chrome: try again with different headers.
                            if ((resp.code == 403 || resp.code == 429 || resp.code == 503) && attempt < attempts) {
                                httpFail = msg
                                try {
                                    Thread.sleep(700L * attempt)
                                } catch (_: InterruptedException) {
                                }
                                return@use
                            }
                            say(msg)
                            sendDl("onDownloadFailed", mapOf("id" to dlId, "message" to msg))
                            return@thread
                        }
                        val body = resp.body ?: throw IOException("Empty response")
                        val cd = resp.header("Content-Disposition") ?: contentDisposition
                        val headerMime = resp.header("Content-Type")?.substringBefore(';')?.trim()
                        val declared = if (!headerMime.isNullOrEmpty()) headerMime
                        else if (!mimeType.isNullOrEmpty()) mimeType
                        else "application/octet-stream"
                        val name = fileNameFor(url, cd, declared)
                        val mime = mimeForName(name, declared)
                        val total = body.contentLength()
                        sendDl(
                            "onDownloadProgress",
                            mapOf("id" to dlId, "name" to name, "received" to 0L, "total" to total)
                        )
                        var lastSent = 0L
                        var count = 0L
                        val counting = object : java.io.FilterInputStream(body.byteStream()) {
                            override fun read(): Int {
                                val r = super.read()
                                if (r >= 0) tick(1)
                                return r
                            }

                            override fun read(b: ByteArray, off: Int, len: Int): Int {
                                val n = super.read(b, off, len)
                                if (n > 0) tick(n)
                                return n
                            }

                            private fun tick(n: Int) {
                                count += n
                                val now = System.currentTimeMillis()
                                if (now - lastSent >= 300) {
                                    lastSent = now
                                    sendDl(
                                        "onDownloadProgress",
                                        mapOf("id" to dlId, "received" to count, "total" to total)
                                    )
                                }
                            }
                        }
                        val saved = counting.use { saveToDownloads(name, mime, it) }
                        say(
                            if (saved.publicFolder) "Saved to Downloads: ${saved.name}"
                            else "Saved in the app's own folder (storage permission was not allowed): ${saved.name}"
                        )
                        sendDl(
                            "onDownloadDone",
                            mapOf(
                                "id" to dlId,
                                "name" to saved.name,
                                "location" to saved.location,
                                "isUri" to saved.isUri,
                                "mime" to mime,
                                "size" to saved.size,
                                "sourceUrl" to url
                            )
                        )
                        return@thread
                    }
                } catch (e: IOException) {
                    lastError = e
                    if (attempt < attempts) {
                        sendDl("onDownloadProgress", mapOf("id" to dlId, "received" to 0L, "total" to -1L, "retry" to attempt))
                        try {
                            Thread.sleep(700L * attempt)
                        } catch (_: InterruptedException) {
                        }
                    }
                } catch (e: Throwable) {
                    lastError = e
                    break
                }
            }
            val host = try { URL(url).host } catch (_: Throwable) { "?" }
            val via = if (ProxyState.active) "proxy on" else "no proxy"
            val msg = httpFail
                ?: "Download failed ($host, $via): ${lastError?.javaClass?.simpleName}: ${lastError?.message}"
            say(msg)
            sendDl("onDownloadFailed", mapOf("id" to dlId, "message" to msg))
        }
    }

    /**
     * Headers of a download request. Tries 1 and 2 look like a Chrome page navigation
     * (language, Sec-Fetch-*, client hints; compression left to OkHttp); try 2 leaves the
     * Referer out. Try 3 is plain: no extras, no compression (the older, proven request).
     */
    private fun browserHeaders(
        b: Request.Builder, attempt: Int, attempts: Int, url: String, userAgent: String?, referer: String?
    ) {
        if (!userAgent.isNullOrEmpty()) b.header("User-Agent", userAgent)
        if (attempt >= attempts) {
            b.header("Accept", "*/*")
            b.header("Accept-Encoding", "identity")
            return
        }
        b.header(
            "Accept",
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8"
        )
        val lang = java.util.Locale.getDefault().toLanguageTag()
        b.header("Accept-Language", if (lang.startsWith("en")) "$lang,en;q=0.9" else "$lang,en;q=0.8")
        b.header("Upgrade-Insecure-Requests", "1")
        val ua = userAgent.orEmpty()
        val chrome = Regex("Chrome/(\\d+)").find(ua)?.groupValues?.get(1)
        if (chrome != null) {
            b.header("sec-ch-ua", "\"Chromium\";v=\"$chrome\", \"Not A(Brand\";v=\"99\", \"Google Chrome\";v=\"$chrome\"")
            b.header("sec-ch-ua-mobile", if (ua.contains("Mobile")) "?1" else "?0")
            b.header("sec-ch-ua-platform", if (ua.contains("Android")) "\"Android\"" else "\"Linux\"")
        }
        val withReferer = attempt == 1 && !referer.isNullOrEmpty()
        val site = if (!withReferer) "none" else try {
            val rh = URL(referer!!).host
            val uh = URL(url).host
            if (rh.equals(uh, true)) "same-origin" else "cross-site"
        } catch (_: Throwable) { "cross-site" }
        b.header("Sec-Fetch-Site", site)
        b.header("Sec-Fetch-Mode", "navigate")
        b.header("Sec-Fetch-User", "?1")
        b.header("Sec-Fetch-Dest", "document")
        if (withReferer) b.header("Referer", referer!!)
    }

    /** Sends a download event to Dart (safe from any thread). */
    private fun sendDl(method: String, args: Map<String, Any?>) {
        mainHandler.post {
            try {
                channel.invokeMethod(method, args)
            } catch (e: Throwable) {
            }
        }
    }

    private fun isGenericMime(m: String?): Boolean {
        val x = m?.lowercase()?.trim().orEmpty()
        return x.isEmpty() || x == "application/octet-stream" || x == "binary/octet-stream" ||
            x == "application/force-download" || x == "application/x-download" ||
            x == "application/download" || x == "application/unknown"
    }

    /**
     * File name for a download. The name sent by the server (Content-Disposition) or in the
     * address is kept AS IS, including its extension. Android's URLUtil.guessFileName is not
     * used because it swaps the extension for ".bin" when the server sends a generic type
     * (an .apk served as application/octet-stream became "file.bin").
     * Only a name WITHOUT an extension gets one, taken from a specific MIME type.
     */
    private fun fileNameFor(url: String, contentDisposition: String?, mime: String?): String {
        var name: String? = null
        val cd = contentDisposition.orEmpty()
        // filename*=UTF-8''name%20here.ext
        Regex("filename\\*\\s*=\\s*[^']*'[^']*'([^;]+)", RegexOption.IGNORE_CASE).find(cd)?.let {
            name = try { java.net.URLDecoder.decode(it.groupValues[1].trim().trim('"'), "UTF-8") } catch (_: Throwable) { null }
        }
        if (name.isNullOrBlank()) {
            Regex("filename\\s*=\\s*\"([^\"]+)\"", RegexOption.IGNORE_CASE).find(cd)?.let { name = it.groupValues[1] }
        }
        if (name.isNullOrBlank()) {
            Regex("filename\\s*=\\s*([^;\"]+)", RegexOption.IGNORE_CASE).find(cd)?.let { name = it.groupValues[1].trim() }
        }
        if (name.isNullOrBlank()) {
            val path = try { Uri.parse(url).lastPathSegment } catch (_: Throwable) { null }
            if (!path.isNullOrBlank()) name = Uri.decode(path)
        }
        var n = (name ?: "").replace(Regex("[\\u0000-\\u001f/\\\\:*?\"<>|]"), "_").trim().trim('.')
        if (n.isEmpty()) n = "download"
        if (n.length > 120) {
            val dot = n.lastIndexOf('.')
            n = if (dot in 1..10) n.substring(0, 120 - (n.length - dot)) + n.substring(dot) else n.substring(0, 120)
        }
        val dot = n.lastIndexOf('.')
        val hasExt = dot > 0 && dot < n.length - 1 && n.length - dot <= 8
        if (!hasExt && !isGenericMime(mime)) {
            val ext = android.webkit.MimeTypeMap.getSingleton().getExtensionFromMimeType(mime!!.lowercase())
            if (!ext.isNullOrEmpty()) n = "$n.$ext"
        }
        return n
    }

    /**
     * MIME type stored with the file. The extension wins when Android knows it (so Android
     * does not rename the file to match a generic or wrong server type); otherwise the
     * server's type is used.
     */
    private fun mimeForName(name: String, declared: String): String {
        val dot = name.lastIndexOf('.')
        if (dot > 0 && dot < name.length - 1) {
            val fromExt = android.webkit.MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(name.substring(dot + 1).lowercase())
            if (!fromExt.isNullOrEmpty()) return fromExt
        }
        return if (isGenericMime(declared)) "application/octet-stream" else declared
    }

    /** HTTP client for downloads: goes through the profile's proxy when one is on, never reuses connections. */
    private fun buildDownloadClient(): OkHttpClient {
        val b = OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .protocols(listOf(Protocol.HTTP_1_1))
            .connectionPool(ConnectionPool(0, 1, TimeUnit.NANOSECONDS))
        if (ProxyState.active) {
            val isSocks = ProxyState.scheme == "socks5"
            val host = ProxyState.host
            val port = ProxyState.port
            val user = ProxyState.username
            val pass = ProxyState.password
            b.proxy(
                Proxy(
                    if (isSocks) Proxy.Type.SOCKS else Proxy.Type.HTTP,
                    InetSocketAddress.createUnresolved(host, port)
                )
            )
            if (user.isNotEmpty()) {
                if (isSocks) {
                    GeoLookup.registerSocksLogin(host, port, user, pass)
                } else {
                    // Answers the proxy's 407 (also for the HTTPS tunnel); gives up after one try.
                    b.proxyAuthenticator { _, response ->
                        if (response.request.header("Proxy-Authorization") != null) null
                        else response.request.newBuilder()
                            .header("Proxy-Authorization", Credentials.basic(user, pass))
                            .build()
                    }
                }
            }
        }
        return b.build()
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

    private fun chromeStyleUa(ua: String): String =
        ua.replace("; wv)", ")").replace("Version/4.0 ", "")

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
            "goBack" -> {
                if (popup != null) closePopup() else if (wv.canGoBack()) wv.goBack()
                result.success(null)
            }
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
            "fillLogin" -> {
                val u = call.argument<String>("username") ?: ""
                val p = call.argument<String>("password") ?: ""
                wv.evaluateJavascript(fillJs(u, p), null)
                result.success(null)
            }
            "clearCache" -> {
                try { wv.clearCache(true) } catch (e: Throwable) { }
                result.success(null)
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
        closePopup()
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

/** Counter for download ids (unique across all WebViews). */
private val downloadSeq = AtomicInteger(0)
