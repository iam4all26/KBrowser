package com.kainuwa.kmultibrowser.profiles

import android.app.Activity
import android.content.pm.PackageManager
import io.flutter.plugin.common.PluginRegistry

/**
 * Asks Android for runtime permissions (camera, microphone, location) on behalf
 * of the WebViews. Shares the activity captured by the plugin.
 */
class PermissionBridge : PluginRegistry.RequestPermissionsResultListener {
    var activity: Activity? = null

    private class Pending(val perms: List<String>, val done: (Map<String, Boolean>) -> Unit)

    private val pending = HashMap<Int, Pending>()
    private var counter = 0

    private fun has(p: String): Boolean =
        activity?.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    /** Calls [done] with the final state of every permission in [perms]. */
    fun request(perms: List<String>, done: (Map<String, Boolean>) -> Unit) {
        val act = activity
        if (act == null) {
            done(perms.associateWith { false })
            return
        }
        val missing = perms.filter { !has(it) }
        if (missing.isEmpty()) {
            done(perms.associateWith { true })
            return
        }
        val code = REQUEST_BASE + (counter++ % 0x100)
        pending[code] = Pending(perms, done)
        try {
            act.requestPermissions(missing.toTypedArray(), code)
        } catch (e: Throwable) {
            pending.remove(code)
            done(perms.associateWith { false })
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        val p = pending.remove(requestCode) ?: return false
        p.done(p.perms.associateWith { has(it) })
        return true
    }

    companion object {
        const val REQUEST_BASE = 0x5000
    }
}
