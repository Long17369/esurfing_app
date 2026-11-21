package com.esurfing.esurfing_app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * 常驻前台服务：只负责持有进程和通知，真正的登录/保活在 Dart SessionHost。
 * 任务从最近列表划掉后服务仍然存活（START_STICKY）。
 */
class SessionService : Service() {
    private var wifiLocation = false

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "校园网保活中"
        val notification = buildNotification(text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val baseType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            } else ServiceInfo.FOREGROUND_SERVICE_TYPE_NONE
            // Keep while-in-use SSID access after the Activity leaves.
            wifiLocation = wifiLocation || intent?.getBooleanExtra(EXTRA_WIFI_LOCATION, false) == true
            if (wifiLocation) {
                try {
                    startForeground(
                        NOTIFICATION_ID, notification,
                        baseType or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                    )
                } catch (error: SecurityException) {
                    wifiLocation = false
                    Log.w("EsurfingSession", "Wi-Fi SSID scope unavailable", error)
                    startForeground(NOTIFICATION_ID, notification, baseType)
                }
            } else {
                startForeground(NOTIFICATION_ID, notification, baseType)
            }
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "连接状态",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "显示校园网连接与保活状态"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(text: String): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Esurfing")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentIntent(openMainActivity(this))
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "esurfing_session"
        private const val NOTIFICATION_ID = 42
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_WIFI_LOCATION = "wifiLocation"

        private fun openMainActivity(context: Context): PendingIntent =
            PendingIntent.getActivity(
                context,
                0,
                Intent.makeMainActivity(ComponentName(context, MainActivity::class.java))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )

        fun start(context: Context, text: String = "校园网保活中", wifiLocation: Boolean = false) {
            val intent = Intent(context, SessionService::class.java)
                .putExtra(EXTRA_TEXT, text)
                .putExtra(EXTRA_WIFI_LOCATION, wifiLocation)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, SessionService::class.java))
        }

        fun update(context: Context, text: String) {
            // A foreground service may run without notification permission, but
            // ordinary NotificationManager.notify calls still require it.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                    PackageManager.PERMISSION_GRANTED
                ) return
            }
            val manager =
                context.getSystemService(NotificationManager::class.java)
            val channel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                NotificationChannel(
                    CHANNEL_ID,
                    "连接状态",
                    NotificationManager.IMPORTANCE_LOW
                )
            } else {
                null
            }
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            val notification = builder
                .setContentTitle("Esurfing")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.stat_sys_upload_done)
                .setContentIntent(openMainActivity(context))
                .setOngoing(true)
                .build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && channel != null) {
                manager.createNotificationChannel(channel)
            }
            manager.notify(NOTIFICATION_ID, notification)
        }
    }
}
