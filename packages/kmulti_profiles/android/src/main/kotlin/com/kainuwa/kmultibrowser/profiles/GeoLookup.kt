package com.kainuwa.kmultibrowser.profiles

import okhttp3.ConnectionPool
import okhttp3.Credentials
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import org.json.JSONObject
import java.net.Authenticator
import java.net.InetSocketAddress
import java.net.PasswordAuthentication
import java.net.Proxy
import java.util.concurrent.TimeUnit

/**
 * Finds the country of the proxy that is currently applied (see [ProxyState]).
 * Goes ONLY through the proxy; when no proxy is active it returns null, so the
 * real address of the phone is never looked up.
 */
object GeoLookup {
    private fun client(): OkHttpClient {
        val b = OkHttpClient.Builder()
            .protocols(listOf(Protocol.HTTP_1_1))
            .connectionPool(ConnectionPool(0, 1, TimeUnit.MILLISECONDS))
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(12, TimeUnit.SECONDS)
            .callTimeout(25, TimeUnit.SECONDS)
        val host = ProxyState.host
        val port = ProxyState.port
        val isSocks = ProxyState.scheme == "socks5"
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
                Authenticator.setDefault(object : Authenticator() {
                    override fun getPasswordAuthentication(): PasswordAuthentication? =
                        if (requestorType == Authenticator.RequestorType.PROXY ||
                            (requestingHost.equals(host, ignoreCase = true) && requestingPort == port)
                        ) PasswordAuthentication(user, pass.toCharArray()) else null
                })
            } else {
                b.proxyAuthenticator { _, response ->
                    if (response.request.header("Proxy-Authorization") != null) null
                    else response.request.newBuilder()
                        .header("Proxy-Authorization", Credentials.basic(user, pass))
                        .build()
                }
            }
        }
        return b.build()
    }

    private fun query(client: OkHttpClient, url: String): Map<String, String>? {
        val req = Request.Builder()
            .url(url)
            .header("User-Agent", "Mozilla/5.0")
            .header("Accept", "application/json")
            .header("Connection", "close")
            .build()
        client.newCall(req).execute().use { r ->
            if (!r.isSuccessful) return null
            val j = JSONObject(r.body?.string() ?: return null)
            if (j.has("success") && !j.optBoolean("success", true)) return null
            val code = j.optString("country_code")
            val name = j.optString("country_name").ifEmpty { j.optString("country") }
            val ip = j.optString("ip")
            if (code.length != 2 || name.isEmpty()) return null
            return mapOf("ip" to ip, "country" to name, "code" to code)
        }
    }

    /** Blocking: call from a background thread. Returns ip, country and code, or null. */
    fun lookup(): Map<String, String>? {
        if (!ProxyState.active) return null
        val c = client()
        for (u in listOf("https://ipwho.is/", "https://ipapi.co/json/")) {
            try {
                val r = query(c, u)
                if (r != null) return r
            } catch (e: Throwable) {
            }
        }
        return null
    }
}
