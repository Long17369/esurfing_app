package com.esurfing.esurfing_app

import android.app.Activity
import java.lang.ref.WeakReference

/** Keeps the background UI reachable without allowing background permission prompts. */
internal class ActivityHost {
    private var activityRef: WeakReference<Activity>? = null
    private var resumed = false

    fun attach(activity: Activity) {
        activityRef = WeakReference(activity)
        resumed = false
    }

    fun resume(activity: Activity) {
        activityRef = WeakReference(activity)
        resumed = true
    }

    fun pause(activity: Activity) {
        if (activityRef?.get() === activity) resumed = false
    }

    fun detach(activity: Activity) {
        if (activityRef?.get() === activity) {
            activityRef = null
            resumed = false
        }
    }

    fun foregroundActivity(): Activity? =
        activityRef?.get()?.takeIf { resumed && !it.isFinishing && !it.isDestroyed }

    fun destroyUi() {
        val activity = activityRef?.get() ?: return
        activity.runOnUiThread {
            // Recheck after dispatch: a resume or a replacement host wins the race.
            if (activityRef?.get() === activity && !resumed &&
                !activity.isFinishing && !activity.isDestroyed &&
                !activity.isChangingConfigurations
            ) {
                activity.finishAndRemoveTask()
            }
        }
    }
}
