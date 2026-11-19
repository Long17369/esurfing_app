package com.esurfing.esurfing_app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * 持有常驻 FlutterEngine，使 Dart 侧 SessionHost 独立于 Activity 生命周期。
 * 前台服务负责把进程留住，Activity 只是这个 engine 的一个视图。
 */
open class EsurfingApplication : android.app.Application() {
    var flutterEngine: FlutterEngine? = null
        private set

    private val activityHost = ActivityHost()
    private var notificationPermissionPending = false

    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        flutterEngine = engine
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startSessionService" -> {
                        SessionService.start(this)
                        result.success(null)
                    }
                    "stopSessionService" -> {
                        SessionService.stop(this)
                        result.success(null)
                    }
                    "updateNotification" -> {
                        SessionService.update(
                            this,
                            call.argument<String>("text") ?: "校园网已连接"
                        )
                        result.success(null)
                    }
                    "requestNotificationPermission" -> {
                        requestNotificationPermission()
                        result.success(null)
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(null)
                    }
                    "wifiStatus" -> result.success(wifiStatus())
                    "requestWifiPermission" -> {
                        requestWifiPermission()
                        result.success(hasWifiPermission())
                    }
                    "openWifiPanel" -> {
                        openWifiPanel()
                        result.success(null)
                    }
                    "destroyUi" -> {
                        destroyUi()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    fun attachActivity(activity: Activity) {
        activityHost.attach(activity)
    }

    fun resumeActivity(activity: Activity) {
        activityHost.resume(activity)
        if (notificationPermissionPending) requestNotificationPermission()
    }

    fun pauseActivity(activity: Activity) {
        activityHost.pause(activity)
    }

    fun detachActivity(activity: Activity) {
        activityHost.detach(activity)
    }

    /**
     * 销毁界面并把它从最近任务里移除，但 FlutterEngine 与前台服务都留着，
     * 保活照常跑。点通知会重新建一个 Activity 挂到同一个 engine 上，
     * Dart 侧 State 与列表位置都还在。
     */
    private fun destroyUi() {
        activityHost.destroyUi()
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            ) {
                notificationPermissionPending = false
                return
            }
            val activity = activityHost.foregroundActivity()
            if (activity == null) {
                // The resident engine can request this before its first UI exists.
                notificationPermissionPending = true
                return
            }
            notificationPermissionPending = false
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_REQUEST
            )
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        val activity = activityHost.foregroundActivity() ?: return
        val intent = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:$packageName")
        )
        try {
            activity.startActivity(intent)
        } catch (_: Exception) {
            activity.startActivity(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            )
        }
    }

    /**
     * 读当前 Wi-Fi 状态。Android 10+ 不允许 App 开关 Wi-Fi，也不允许静默连接，
     * 所以只提供「当前 SSID / 射频状态 / 权限状态」，连接一律交给系统。
     */
    private fun wifiStatus(): Map<String, Any?> {
        val manager = applicationContext
            .getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return mapOf("supported" to false)
        val enabled = try {
            manager.isWifiEnabled
        } catch (_: Exception) {
            false
        }
        val granted = hasWifiPermission()
        var ssid = ""
        if (granted) {
            ssid = try {
                @Suppress("DEPRECATION")
                manager.connectionInfo?.ssid ?: ""
            } catch (_: Exception) {
                ""
            }
            ssid = ssid.trim().removeSurrounding("\"")
            // 没权限 / 没连上时系统会返回 <unknown ssid> 或一串 0。
            if (ssid == "<unknown ssid>" || ssid == "0x" ||
                ssid == "02:00:00:00:00:00" || ssid.startsWith("0x0")
            ) {
                ssid = ""
            }
        }
        return mapOf(
            "supported" to true,
            "enabled" to enabled,
            "ssid" to ssid,
            "permissionGranted" to granted
        )
    }

    private fun hasWifiPermission(): Boolean {
        // SSID is location-sensitive; NEARBY_WIFI_DEVICES alone does not grant it.
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestWifiPermission() {
        val activity = activityHost.foregroundActivity() ?: return
        if (hasWifiPermission()) return
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(
                Manifest.permission.NEARBY_WIFI_DEVICES,
                Manifest.permission.ACCESS_COARSE_LOCATION,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
        } else {
            // Android 12+ ignores a fine-only runtime location request.
            arrayOf(
                Manifest.permission.ACCESS_COARSE_LOCATION,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
        }
        activity.requestPermissions(permissions, WIFI_REQUEST)
    }

    /** Android 10+ 无法直接开关 Wi-Fi，只能唤起系统面板让用户操作。 */
    private fun openWifiPanel() {
        val activity = activityHost.foregroundActivity() ?: return
        val manager = applicationContext
            .getSystemService(Context.WIFI_SERVICE) as? WifiManager
        // Android 9 及以下还能直接打开射频，顺手打开省一步。
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q && manager != null) {
            try {
                if (!manager.isWifiEnabled) {
                    @Suppress("DEPRECATION")
                    manager.isWifiEnabled = true
                }
            } catch (_: Exception) {
                // 忽略：下面还会打开系统面板。
            }
        }
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Intent(Settings.Panel.ACTION_WIFI)
        } else {
            Intent(Settings.ACTION_WIFI_SETTINGS)
        }
        try {
            activity.startActivity(intent)
        } catch (_: Exception) {
            // 打不开就算了，UI 会提示手动连接。
        }
    }

    companion object {
        private const val CHANNEL = "esurfing/android"
        private const val NOTIFICATION_REQUEST = 1001
        private const val WIFI_REQUEST = 1002
    }
}
