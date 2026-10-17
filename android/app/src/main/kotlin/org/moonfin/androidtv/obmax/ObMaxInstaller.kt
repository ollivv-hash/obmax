package org.moonfin.androidtv.obmax

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * OB Max over-the-air updates: installs a downloaded APK through
 * [PackageInstaller]. Dart has already checked its SHA-256.
 *
 * Methods on `obmax/installer`:
 * - `canInstall` -> Boolean: whether "install unknown apps" is granted.
 * - `openInstallPermission`: opens the system screen that grants it.
 * - `install(path)` -> String: "pending" once the system confirmation shows,
 *   or an error message. The final result arrives later as `onStatus`.
 */
class ObMaxInstaller private constructor(
    private val activity: Activity,
    private val channel: MethodChannel,
) {
    companion object {
        private const val CHANNEL = "obmax/installer"
        private const val ACTION_STATUS = "com.example.obmax.INSTALL_STATUS"

        fun register(engine: FlutterEngine, activity: Activity) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            val installer = ObMaxInstaller(activity, channel)
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(installer.canInstall())
                    "openInstallPermission" -> {
                        installer.openInstallPermission()
                        result.success(null)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "path missing", null)
                        } else {
                            result.success(installer.install(path))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private var receiverRegistered = false

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val status = intent.getIntExtra(
                PackageInstaller.EXTRA_STATUS,
                PackageInstaller.STATUS_FAILURE,
            )
            when (status) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    @Suppress("DEPRECATION")
                    val confirm = if (Build.VERSION.SDK_INT >= 33) {
                        intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                    } else {
                        intent.getParcelableExtra(Intent.EXTRA_INTENT)
                    }
                    confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    if (confirm != null) activity.startActivity(confirm)
                }
                else -> {
                    val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    activity.runOnUiThread {
                        channel.invokeMethod(
                            "onStatus",
                            mapOf("status" to status, "message" to message),
                        )
                    }
                }
            }
        }
    }

    private fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < 26 ||
            activity.packageManager.canRequestPackageInstalls()

    private fun openInstallPermission() {
        val intent = if (Build.VERSION.SDK_INT >= 26) {
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}"),
            )
        } else {
            @Suppress("DEPRECATION")
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        try {
            activity.startActivity(intent)
        } catch (_: Exception) {
            // Some TV builds lack the per-app screen: fall back to the list.
            if (Build.VERSION.SDK_INT >= 26) {
                activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES))
            }
        }
    }

    private fun install(path: String): String {
        val apk = File(path)
        if (!apk.exists()) return "Fichier introuvable"
        if (!canInstall()) return "permission"
        ensureReceiver()
        val installer = activity.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        ).apply {
            setAppPackageName(activity.packageName)
            if (Build.VERSION.SDK_INT >= 31) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
        }
        return try {
            val sessionId = installer.createSession(params)
            installer.openSession(sessionId).use { session ->
                apk.inputStream().use { input ->
                    session.openWrite("obmax.apk", 0, apk.length()).use { out ->
                        input.copyTo(out)
                        session.fsync(out)
                    }
                }
                val intent = Intent(ACTION_STATUS).setPackage(activity.packageName)
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                val pending = PendingIntent.getBroadcast(activity, sessionId, intent, flags)
                session.commit(pending.intentSender)
            }
            "pending"
        } catch (e: Exception) {
            e.message ?: e.javaClass.simpleName
        }
    }

    private fun ensureReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter(ACTION_STATUS)
        if (Build.VERSION.SDK_INT >= 33) {
            activity.applicationContext.registerReceiver(
                statusReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            activity.applicationContext.registerReceiver(statusReceiver, filter)
        }
        receiverRegistered = true
    }
}
