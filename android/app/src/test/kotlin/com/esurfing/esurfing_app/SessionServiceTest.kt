package com.esurfing.esurfing_app

import android.Manifest
import android.app.Application
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class SessionServiceTest {
    @Test
    fun deniedNotificationPermissionDoesNotPostAnOrdinaryUpdate() {
        val context = RuntimeEnvironment.getApplication()
        SessionService.update(context, "test")
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        assertEquals(0, manager.activeNotifications.size)
    }

    @Test
    fun grantedNotificationUpdateReopensTheMainActivity() {
        val context = RuntimeEnvironment.getApplication()
        shadowOf(context).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        SessionService.update(context, "offline test")
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notification = manager.activeNotifications.single().notification
        assertMainTaskIntent(context, notification.contentIntent)
    }

    @Test
    fun stickyForegroundServiceKeepsItsReopenNotificationWithoutAUi() {
        val service = Robolectric.buildService(SessionService::class.java).create().get()
        assertEquals(Service.START_STICKY, service.onStartCommand(null, 0, 1))
        assertNotNull(shadowOf(service).lastForegroundNotification)
        val notification = shadowOf(service).lastForegroundNotification
        assertMainTaskIntent(service, notification.contentIntent)
    }

    private fun assertMainTaskIntent(context: Context, pendingIntent: PendingIntent) {
        val main = ComponentName(context, MainActivity::class.java)
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val open = shadowOf(pendingIntent).savedIntent
        assertEquals(main, launch?.component)
        assertEquals(main, open.component)
        assertEquals(Intent.ACTION_MAIN, open.action)
        assertEquals(setOf(Intent.CATEGORY_LAUNCHER), open.categories)
        assertEquals(
            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
            open.flags
        )
        val activity = context.packageManager.getActivityInfo(main, 0)
        assertEquals(ActivityInfo.LAUNCH_SINGLE_TASK, activity.launchMode)
        assertEquals(context.packageName, activity.taskAffinity)
    }
}
