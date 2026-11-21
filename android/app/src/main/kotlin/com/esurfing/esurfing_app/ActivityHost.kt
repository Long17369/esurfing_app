package com.esurfing.esurfing_app

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.lang.ref.WeakReference
import java.util.concurrent.TimeUnit

/** Main-thread owner of the current Activity and its background deadline. */
internal class ActivityHost(private val onUiRemoved: () -> Unit = {}) {
    private val handler = Handler(Looper.getMainLooper())
    private var activityRef: WeakReference<Activity>? = null
    private var resumed = false
    private var stoppedAt: Long? = null
    private var delayMillis = 0L
    private var pendingRemoval: Runnable? = null

    fun attach(activity: Activity) {
        clearStoppedInterval()
        activityRef = WeakReference(activity)
        resumed = false
    }

    fun start(activity: Activity) {
        if (activityRef?.get() === activity) clearStoppedInterval()
    }

    fun resume(activity: Activity) {
        if (activityRef?.get() !== activity) return
        clearStoppedInterval()
        resumed = true
    }

    fun pause(activity: Activity) {
        if (activityRef?.get() === activity) resumed = false
    }

    fun stop(activity: Activity) {
        if (activityRef?.get() !== activity) return
        resumed = false
        if (!canRemove(activity) || stoppedAt != null) return
        stoppedAt = SystemClock.uptimeMillis()
        scheduleRemoval()
    }

    fun detach(activity: Activity) {
        if (activityRef?.get() === activity) {
            clearStoppedInterval()
            activityRef = null
            resumed = false
        }
    }

    fun foregroundActivity(): Activity? =
        activityRef?.get()?.takeIf { resumed && !it.isFinishing && !it.isDestroyed }

    fun setBackgroundDestroyMinutes(minutes: Long) {
        val delay = TimeUnit.MINUTES.toMillis(minutes.coerceAtLeast(0))
        if (delay == delayMillis) return
        delayMillis = delay
        scheduleRemoval()
    }

    private fun clearStoppedInterval() {
        stoppedAt = null
        cancelRemoval()
    }

    private fun cancelRemoval() {
        pendingRemoval?.let(handler::removeCallbacks)
        pendingRemoval = null
    }

    private fun scheduleRemoval() {
        cancelRemoval()
        val stopped = stoppedAt ?: return
        val owner = activityRef ?: return
        if (delayMillis == 0L) return

        val removal = object : Runnable {
            override fun run() {
                if (pendingRemoval !== this) return
                pendingRemoval = null
                val activity = owner.get() ?: return
                if (activityRef !== owner || stoppedAt != stopped ||
                    resumed || !canRemove(activity)
                ) return

                stoppedAt = null
                activity.finishAndRemoveTask()
                onUiRemoved()
            }
        }
        pendingRemoval = removal
        handler.postAtTime(removal, stopped + delayMillis.coerceAtMost(Long.MAX_VALUE - stopped))
    }

    private fun canRemove(activity: Activity): Boolean =
        !activity.isFinishing && !activity.isDestroyed && !activity.isChangingConfigurations
}
