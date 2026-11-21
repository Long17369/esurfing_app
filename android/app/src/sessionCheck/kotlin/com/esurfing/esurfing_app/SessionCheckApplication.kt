package com.esurfing.esurfing_app

import android.app.NotificationManager
import android.app.Activity
import android.app.ActivityManager
import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Process
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

/** Compiled only into the explicitly requested isolated debug APK. */
class SessionCheckApplication : EsurfingApplication() {
    lateinit var checkChannel: MethodChannel

    override fun onCreate() {
        super.onCreate()
        var created = 0
        var destroyed = 0
        registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, state: Bundle?) { created++ }
            override fun onActivityDestroyed(activity: Activity) { destroyed++ }
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
        })
        checkChannel = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "esurfing/session-check")
        checkChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "evidence" -> {
                    val tasks = getSystemService(ActivityManager::class.java).appTasks
                        .map { it.taskInfo.persistentId }
                    val text = JSONObject(call.arguments.toString())
                        .put("engine", System.identityHashCode(flutterEngine))
                        .put("pid", Process.myPid())
                        .put("activitiesCreated", created)
                        .put("activitiesDestroyed", destroyed)
                        .put("recentTaskIds", JSONArray(tasks))
                        .toString()
                    File(filesDir, "session-check.json").writeText(text)
                    Log.i("SessionCheck", "engine=${System.identityHashCode(flutterEngine)} $text")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}

class SessionCheckReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext as SessionCheckApplication
        when (val command = intent.getStringExtra("command")) {
            "notification" -> {
                val notifications = context.getSystemService(NotificationManager::class.java).activeNotifications
                check(notifications.isNotEmpty()) { "No session notification to reopen" }
                notifications.first().notification.contentIntent.send()
            }
            else -> app.checkChannel.invokeMethod(command ?: "status", null)
        }
    }
}
