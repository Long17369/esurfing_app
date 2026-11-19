package com.esurfing.esurfing_app

import android.app.Activity
import android.app.Application
import android.os.Looper
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class ActivityHostTest {
    @Test
    fun pausedActivityRemainsDestroyableButCannotPresentPermissions() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val host = ActivityHost()
        host.attach(activity)
        host.resume(activity)
        assertSame(activity, host.foregroundActivity())

        host.pause(activity)
        assertNull(host.foregroundActivity())
        host.destroyUi()

        assertTrue(activity.isFinishing)
    }

    @Test
    fun foregroundResumeWinsAgainstQueuedBackgroundDestroy() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val host = ActivityHost()
        host.resume(activity)
        host.pause(activity)

        Thread { host.destroyUi() }.apply { start(); join() }
        host.resume(activity)
        shadowOf(Looper.getMainLooper()).idle()

        assertFalse(activity.isFinishing)
        assertSame(activity, host.foregroundActivity())
    }

    @Test
    fun recreationAndLateOldDestroyDoNotClearTheNewActivity() {
        val old = Robolectric.buildActivity(Activity::class.java).setup().get()
        val replacement = Robolectric.buildActivity(Activity::class.java).setup().get()
        val host = ActivityHost()
        host.resume(old)
        host.pause(old)
        Thread { host.destroyUi() }.apply { start(); join() }

        host.attach(replacement)
        host.resume(replacement)
        host.detach(old)
        host.pause(old)
        shadowOf(Looper.getMainLooper()).idle()

        assertFalse(old.isFinishing)
        assertFalse(replacement.isFinishing)
        assertSame(replacement, host.foregroundActivity())
    }

    @Test
    fun notificationReopenUsesANewHostAfterBackgroundRemoval() {
        val old = Robolectric.buildActivity(Activity::class.java).setup().get()
        val host = ActivityHost()
        host.resume(old)
        host.pause(old)
        host.destroyUi()
        assertTrue(old.isFinishing)
        host.detach(old)
        host.destroyUi()

        val reopened = Robolectric.buildActivity(Activity::class.java).setup().get()
        host.attach(reopened)
        host.resume(reopened)
        host.destroyUi()
        assertFalse(reopened.isFinishing)
        assertSame(reopened, host.foregroundActivity())
        host.pause(reopened)
        host.destroyUi()
        assertTrue(reopened.isFinishing)
    }

    @Test
    fun finishingOrDestroyedActivitiesCannotPresentPermissions() {
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = controller.get()
        val host = ActivityHost()
        host.resume(activity)
        activity.finish()
        assertNull(host.foregroundActivity())
        controller.pause().stop().destroy()
        host.destroyUi()
        assertNull(host.foregroundActivity())
    }
}
