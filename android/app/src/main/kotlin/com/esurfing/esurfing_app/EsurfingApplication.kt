package com.esurfing.esurfing_app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * 持有常驻 FlutterEngine，使 Dart 侧 SessionHost 独立于 Activity 生命周期。
 * 前台服务负责把进程留住，Activity 只是这个 engine 的一个视图。
 */
class EsurfingApplication : android.app.Application() {
    var flutterEngine: FlutterEngine? = null
        private set

    private var activityRef: WeakReference<Activity>? = null

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
                    else -> result.notImplemented()
                }
            }
    }

    fun attachActivity(activity: Activity) {
        activityRef = WeakReference(activity)
    }

    fun detachActivity(activity: Activity) {
        if (activityRef?.get() === activity) activityRef = null
    }

    private fun requestNotificationPermission() {
        val activity = activityRef?.get() ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.requestPermissions(
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_REQUEST
            )
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        val activity = activityRef?.get() ?: return
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

    companion object {
        private const val CHANNEL = "esurfing/android"
        private const val NOTIFICATION_REQUEST = 1001
    }
}
