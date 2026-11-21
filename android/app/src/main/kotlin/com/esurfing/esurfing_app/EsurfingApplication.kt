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
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.net.Proxy
import java.net.URL
import java.util.concurrent.Executors
import javax.net.ssl.HttpsURLConnection

/**
 * 持有常驻 FlutterEngine，使 Dart 侧 SessionHost 独立于 Activity 生命周期。
 * 前台服务负责把进程留住，Activity 只是这个 engine 的一个视图。
 */
open class EsurfingApplication : android.app.Application() {
    var flutterEngine: FlutterEngine? = null
        private set

    private var androidChannel: MethodChannel? = null
    private val activityHost = ActivityHost {
        androidChannel?.invokeMethod("backgroundUiRemoved", null)
    }
    private var notificationPermissionPending = false
    private var pendingWifiLocation = false
    private val wifiProbeExecutor by lazy { Executors.newSingleThreadExecutor() }
    private val wifiNetworks by lazy(LazyThreadSafetyMode.NONE) {
        WifiNetworkMonitor(this, ::hasWifiPermission)
    }

    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this)
        val wifiMonitor = wifiNetworks
        EventChannel(engine.dartExecutor.binaryMessenger, WIFI_NETWORK_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    wifiMonitor.listen { events.success(it) }
                }

                override fun onCancel(arguments: Any?) {
                    wifiMonitor.listen(null)
                }
            })
        flutterEngine = engine
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        androidChannel = channel
        channel
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startSessionService" -> {
                        val requested = call.argument<Boolean>("wifiLocation") == true
                        val wifiLocation = requested && hasWifiPermission() &&
                            (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                                activityHost.foregroundActivity() != null)
                        try {
                            SessionService.start(this, wifiLocation = wifiLocation)
                            pendingWifiLocation = requested && !wifiLocation
                            result.success(wifiLocation)
                        } catch (error: IllegalStateException) {
                            result.error("foreground_service", error.message, null)
                        } catch (error: SecurityException) {
                            result.error("foreground_service", error.message, null)
                        }
                    }
                    "stopSessionService" -> {
                        pendingWifiLocation = false
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
                    "wifiNetworkSnapshot" -> result.success(wifiNetworks.snapshot())
                    "probeWifiInternet" -> {
                        val handle = call.argument<Number>("handle")?.toLong()
                        val network = handle?.let(wifiMonitor::unvalidatedInternetLink)
                        if (network == null) {
                            result.success(null)
                        } else {
                            wifiProbeExecutor.execute {
                                try {
                                    val connection = network.openConnection(
                                        URL("https://connect.rom.miui.com/generate_204"), Proxy.NO_PROXY,
                                    ) as HttpsURLConnection
                                    try {
                                        connection.connectTimeout = 4000
                                        connection.readTimeout = 4000
                                        connection.instanceFollowRedirects = false
                                        connection.useCaches = false
                                        result.success(connection.responseCode == 204)
                                    } finally {
                                        connection.disconnect()
                                    }
                                } catch (error: IOException) {
                                    Log.i("EsurfingSession", "Scoped HTTPS probe failed: ${error.javaClass.simpleName}")
                                    result.success(false)
                                } catch (error: SecurityException) {
                                    result.error("wifi_probe", error.message, null)
                                }
                            }
                        }
                    }
                    "requestWifiRevalidation" -> {
                        val handle = call.argument<Number>("handle")?.toLong()
                        try {
                            result.success(handle != null && wifiMonitor.requestRevalidation(handle))
                        } catch (error: SecurityException) {
                            result.error("wifi_revalidation", error.message, null)
                        }
                    }
                    "requestWifiPermission" -> {
                        requestWifiPermission()
                        result.success(hasWifiPermission())
                    }
                    "openWifiPanel" -> {
                        openWifiPanel()
                        result.success(null)
                    }
                    "setBackgroundDestroyMinutes" -> {
                        activityHost.setBackgroundDestroyMinutes(
                            call.argument<Number>("minutes")?.toLong() ?: 0L
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
    }

    fun attachActivity(activity: Activity) {
        activityHost.attach(activity)
    }

    fun startActivityHost(activity: Activity) {
        activityHost.start(activity)
    }

    fun resumeActivity(activity: Activity) {
        activityHost.resume(activity)
        if (activityHost.foregroundActivity() !== activity) return
        wifiNetworks.snapshot()
        if (pendingWifiLocation && hasWifiPermission()) {
            try {
                SessionService.start(this, wifiLocation = true)
                pendingWifiLocation = false
            } catch (error: IllegalStateException) {
                Log.w("EsurfingSession", "Unable to update foreground Wi-Fi scope", error)
            } catch (error: SecurityException) {
                Log.w("EsurfingSession", "Unable to update foreground Wi-Fi scope", error)
            }
        }
        if (notificationPermissionPending) requestNotificationPermission()
    }

    fun pauseActivity(activity: Activity) {
        activityHost.pause(activity)
    }

    fun stopActivityHost(activity: Activity) {
        activityHost.stop(activity)
    }

    fun detachActivity(activity: Activity) {
        activityHost.detach(activity)
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
        wifiNetworks.snapshot()
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

    internal fun onWifiPermissionResult(requestCode: Int) {
        if (requestCode == WIFI_REQUEST) wifiNetworks.snapshot(forceEvent = true)
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
        private const val WIFI_NETWORK_EVENTS = "esurfing/android/wifi_networks"
        private const val NOTIFICATION_REQUEST = 1001
        private const val WIFI_REQUEST = 1002
    }
}
