package com.kainuwa.kmultibrowser.profiles

/** The proxy that is currently applied to all WebViews of the app (set from Flutter). */
object ProxyState {
    @Volatile var active: Boolean = false
    @Volatile var scheme: String = ""
    @Volatile var host: String = ""
    @Volatile var port: Int = 0
    @Volatile var username: String = ""
    @Volatile var password: String = ""

    fun set(scheme: String, host: String, port: Int, username: String, password: String) {
        this.scheme = scheme
        this.host = host
        this.port = port
        this.username = username
        this.password = password
        this.active = true
    }

    fun clear() {
        active = false
        scheme = ""
        host = ""
        port = 0
        username = ""
        password = ""
    }
}
