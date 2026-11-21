package com.esurfing.esurfing_app

import android.app.Activity
import android.app.Application
import android.os.Looper
import java.util.concurrent.TimeUnit.SECONDS
import org.junit.Assert.assertEquals
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
    private fun advance(seconds: Long) {
        shadowOf(Looper.getMainLooper()).idleFor(seconds, SECONDS)
    }

    @Test
    fun pauseBlocksPermissionsButOnlyStopStartsTheTimer() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        var removals = 0
        val host = ActivityHost { removals++ }
        host.setBackgroundDestroyMinutes(1)
        host.attach(activity)
        host.resume(activity)
        assertSame(activity, host.foregroundActivity())

        host.pause(activity)
        assertNull(host.foregroundActivity())
        advance(120)
        assertFalse(activity.isFinishing)

        host.stop(activity)
        advance(59)
        host.stop(activity)
        assertFalse(activity.isFinishing)
        advance(1)
        assertTrue(activity.isFinishing)
        advance(60)
        assertEquals(1, removals)
    }

    @Test
    fun startCancelsRemovalBeforeResumeAndTheNextStopGetsItsOwnDeadline() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val host = ActivityHost()
        host.setBackgroundDestroyMinutes(1)
        host.attach(activity)
        host.resume(activity)
        host.stop(activity)
        advance(59)

        host.start(activity)
        assertNull(host.foregroundActivity())
        advance(1)
        assertFalse(activity.isFinishing)
        host.resume(activity)
        assertSame(activity, host.foregroundActivity())
        host.stop(activity)
        advance(59)
        assertFalse(activity.isFinishing)
        advance(1)
        assertTrue(activity.isFinishing)
    }

    @Test
    fun recreationAndStaleLifecycleCallbacksCannotRemoveTheReplacement() {
        val old = Robolectric.buildActivity(Activity::class.java).setup().get()
        val replacement = Robolectric.buildActivity(Activity::class.java).setup().get()
        val host = ActivityHost()
        host.setBackgroundDestroyMinutes(1)
        host.attach(old)
        host.resume(old)
        host.stop(old)
        advance(59)

        host.attach(replacement)
        host.resume(replacement)
        host.resume(old)
        host.stop(old)
        host.detach(old)
        host.pause(old)
        advance(60)

        assertFalse(old.isFinishing)
        assertFalse(replacement.isFinishing)
        assertSame(replacement, host.foregroundActivity())
    }

    @Test
    fun configChangeAndDestroyInvalidatePendingRemoval() {
        val old = Robolectric.buildActivity(ReconfiguringActivity::class.java).setup().get()
        val host = ActivityHost()
        host.setBackgroundDestroyMinutes(1)
        host.attach(old)
        host.stop(old)
        old.reconfiguring = true
        advance(60)
        assertFalse(old.isFinishing)
        host.detach(old)

        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        host.attach(activity)
        host.stop(activity)
        host.detach(activity)
        advance(60)
        assertFalse(activity.isFinishing)
    }

    @Test
    fun disabledTimeoutCancelsAndChangesStillUseTheOriginalStopTime() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val host = ActivityHost()
        host.setBackgroundDestroyMinutes(1)
        host.attach(activity)
        host.stop(activity)
        advance(30)
        host.setBackgroundDestroyMinutes(0)
        advance(30)
        assertFalse(activity.isFinishing)
        host.setBackgroundDestroyMinutes(-1)
        advance(30)
        assertFalse(activity.isFinishing)
        host.setBackgroundDestroyMinutes(2)
        advance(29)
        assertFalse(activity.isFinishing)
        advance(1)
        assertTrue(activity.isFinishing)
    }

    @Test
    fun aNewHostCanStartItsOwnIntervalAfterRemoval() {
        val old = Robolectric.buildActivity(Activity::class.java).setup().get()
        val reopened = Robolectric.buildActivity(Activity::class.java).setup().get()
        val host = ActivityHost()
        host.setBackgroundDestroyMinutes(1)
        host.attach(old)
        host.stop(old)
        advance(60)
        assertTrue(old.isFinishing)
        host.detach(old)

        host.attach(reopened)
        host.resume(reopened)
        advance(60)
        assertFalse(reopened.isFinishing)
        host.stop(reopened)
        advance(60)
        assertTrue(reopened.isFinishing)
    }

    @Test
    fun finishingOrDestroyedActivitiesCannotPresentPermissions() {
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = controller.get()
        val host = ActivityHost()
        host.attach(activity)
        host.resume(activity)
        activity.finish()
        assertNull(host.foregroundActivity())
        controller.pause().stop().destroy()
        assertNull(host.foregroundActivity())
    }

    class ReconfiguringActivity : Activity() {
        var reconfiguring = false

        override fun isChangingConfigurations(): Boolean = reconfiguring
    }
}
