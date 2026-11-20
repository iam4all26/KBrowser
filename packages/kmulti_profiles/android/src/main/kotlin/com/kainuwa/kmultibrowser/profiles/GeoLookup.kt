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
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/**
 * Finds the country behind an address. Three modes:
 *  - [lookup]: the proxy that is currently applied (see [ProxyState]);
 *  - [lookupVia]: one given proxy (used to show flags when choosing a proxy);
 *  - [lookupDirect]: the phone's own connection, only while NO proxy is applied.
 */
object GeoLookup {
    // SOCKS logins by "host:port". One shared Authenticator answers for all of them,
    // so several lookups and downloads can run at the same time.
    private val socksLogins = ConcurrentHashMap<String, Pair<String, String>>()

    /** Registers a SOCKS5 login and (re)installs the shared Authenticator. */
    fun registerSocksLogin(host: String, port: Int, user: String, pass: String) {
        socksLogins["${host.lowercase()}:$port"] = Pair(user, pass)
        Authenticator.setDefault(object : Authenticator() {
            override fun getPasswordAuthentication(): PasswordAuthentication? {
                val key = "${requestingHost.orEmpty().lowercase()}:$requestingPort"
                val c = socksLogins[key] ?: return null
                return PasswordAuthentication(c.first, c.second.toCharArray())
            }
        })
    }

    private fun client(
        scheme: String?, host: String, port: Int, user: String, pass: String
    ): OkHttpClient {
        val b = OkHttpClient.Builder()
            .protocols(listOf(Protocol.HTTP_1_1))
            .connectionPool(ConnectionPool(0, 1, TimeUnit.MILLISECONDS))
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(12, TimeUnit.SECONDS)
            .callTimeout(25, TimeUnit.SECONDS)
        if (scheme == null) {
            b.proxy(Proxy.NO_PROXY)
            return b.build()
        }
        val isSocks = scheme == "socks5"
        b.proxy(
            Proxy(
                if (isSocks) Proxy.Type.SOCKS else Proxy.Type.HTTP,
                InetSocketAddress.createUnresolved(host, port)
            )
        )
        if (user.isNotEmpty()) {
            if (isSocks) {
                registerSocksLogin(host, port, user, pass)
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

    private fun run(c: OkHttpClient): Map<String, String>? {
        for (u in listOf("https://ipwho.is/", "https://ipapi.co/json/")) {
            try {
                val r = query(c, u)
                if (r != null) return r
            } catch (e: Throwable) {
            }
        }
        return null
    }

    /** Blocking: call from a background thread. The proxy now applied to the app. */
    fun lookup(): Map<String, String>? {
        if (!ProxyState.active) return null
        return run(client(ProxyState.scheme, ProxyState.host, ProxyState.port, ProxyState.username, ProxyState.password))
    }

    /** Blocking: one given proxy, whether or not it is applied. */
    fun lookupVia(scheme: String, host: String, port: Int, user: String, pass: String): Map<String, String>? {
        if (scheme != "http" && scheme != "https" && scheme != "socks5") return null
        return run(client(scheme, host, port, user, pass))
    }

    /** Blocking: the phone's own connection. Refused while a proxy is applied. */
    fun lookupDirect(): Map<String, String>? {
        if (ProxyState.active) return null
        return run(client(null, "", 0, "", ""))
    }
}
