package com.esurfing.esurfing_app

import android.Manifest
import android.app.Application
import android.app.NotificationManager
import android.app.Service
import android.content.Context
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
        val open = shadowOf(notification.contentIntent).savedIntent
        assertEquals(MainActivity::class.java.name, open.component?.className)
    }

    @Test
    fun stickyForegroundServiceKeepsItsReopenNotificationWithoutAUi() {
        val service = Robolectric.buildService(SessionService::class.java).create().get()
        assertEquals(Service.START_STICKY, service.onStartCommand(null, 0, 1))
        assertNotNull(shadowOf(service).lastForegroundNotification)
        val notification = shadowOf(service).lastForegroundNotification
        val open = shadowOf(notification.contentIntent).savedIntent
        assertEquals(MainActivity::class.java.name, open.component?.className)
    }
}
