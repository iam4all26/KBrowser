package com.kainuwa.kmultibrowser.profiles

import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
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
 * to the default (shared) profile.
 */
class KWebView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    private val profileName: String
) : PlatformView, MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "kmulti/webview_$viewId")
    private var webView: WebView? = null
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
            wv.settings.javaScriptEnabled = true
            wv.settings.domStorageEnabled = true
            wv.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(
                    view: WebView,
                    request: WebResourceRequest
                ): Boolean = false

                override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                    notifyPage(view, url)
                }

                override fun onPageFinished(view: WebView, url: String?) {
                    ProfileStore.getInstance().getProfile(profileName)?.cookieManager?.flush()
                    notifyPage(view, url)
                }
            }
            webView = wv
            wv
        } catch (e: Throwable) {
            errorView(context, "Could not open profile $profileName: ${e.message}")
        }
    }

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
            "goBack" -> { if (wv.canGoBack()) wv.goBack(); result.success(null) }
            "goForward" -> { if (wv.canGoForward()) wv.goForward(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    override fun getView(): View = root

    override fun dispose() {
        channel.setMethodCallHandler(null)
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
