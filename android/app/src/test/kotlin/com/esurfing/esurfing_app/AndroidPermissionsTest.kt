package com.esurfing.esurfing_app

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.ContextWrapper
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class AndroidPermissionsTest {
    private fun application(): EsurfingApplication {
        val app = EsurfingApplication()
        ContextWrapper::class.java.getDeclaredMethod("attachBaseContext", Context::class.java)
            .apply { isAccessible = true }
            .invoke(app, RuntimeEnvironment.getApplication())
        return app
    }

    private fun invoke(app: EsurfingApplication, method: String): Any? =
        EsurfingApplication::class.java.getDeclaredMethod(method)
            .apply { isAccessible = true }.invoke(app)

    @Test
    fun engineStartupNotificationRequestWaitsForAResumedActivity() {
        val app = application()
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        invoke(app, "requestNotificationPermission")
        app.attachActivity(activity)
        assertNull(shadowOf(activity).lastRequestedPermission)
        app.resumeActivity(activity)
        assertArrayEquals(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            shadowOf(activity).lastRequestedPermission.requestedPermissions
        )
    }

    @Test
    fun backgroundWifiRequestsCannotShowPermissionOrSettingsUi() {
        val app = application()
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        app.attachActivity(activity)
        app.resumeActivity(activity)
        app.pauseActivity(activity)
        invoke(app, "requestWifiPermission")
        invoke(app, "openWifiPanel")
        invoke(app, "requestIgnoreBatteryOptimizations")
        assertNull(shadowOf(activity).lastRequestedPermission)
        assertNull(shadowOf(activity).nextStartedActivity)
        app.resumeActivity(activity)
        invoke(app, "requestWifiPermission")
        assertArrayEquals(
            arrayOf(
                Manifest.permission.NEARBY_WIFI_DEVICES,
                Manifest.permission.ACCESS_COARSE_LOCATION,
                Manifest.permission.ACCESS_FINE_LOCATION
            ),
            shadowOf(activity).lastRequestedPermission.requestedPermissions
        )
    }

    @Test
    fun nearbyWifiPermissionIsNotEnoughToReadLocationSensitiveSsid() {
        val app = application()
        val permissions = shadowOf(RuntimeEnvironment.getApplication())
        permissions.grantPermissions(Manifest.permission.NEARBY_WIFI_DEVICES)
        assertFalse(invoke(app, "hasWifiPermission") as Boolean)
        permissions.grantPermissions(Manifest.permission.ACCESS_FINE_LOCATION)
        assertTrue(invoke(app, "hasWifiPermission") as Boolean)
    }

    @Test
    fun wifiPermissionResultPublishesEvenWithoutAnotherActivityResume() {
        val app = application()
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        app.attachActivity(activity)
        app.resumeActivity(activity)
        val monitor = invoke(app, "getWifiNetworks") as WifiNetworkMonitor
        val grants = mutableListOf<Boolean>()
        monitor.listen { grants.add(it.getValue("permissionGranted") as Boolean) }
        invoke(app, "requestWifiPermission")
        val request = shadowOf(activity).lastRequestedPermission.requestCode

        app.onWifiPermissionResult(request + 1)
        assertEquals(listOf(false), grants)
        app.onWifiPermissionResult(request)
        assertEquals(listOf(false, false), grants)
        shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION
        )
        app.onWifiPermissionResult(request)
        assertEquals(listOf(false, false, true), grants)
    }

    @Test
    @Config(sdk = [31])
    fun android12RequestsCoarseAndFineLocationTogether() {
        val app = application()
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        app.attachActivity(activity)
        app.resumeActivity(activity)
        invoke(app, "requestWifiPermission")
        assertArrayEquals(
            arrayOf(
                Manifest.permission.ACCESS_COARSE_LOCATION,
                Manifest.permission.ACCESS_FINE_LOCATION
            ),
            shadowOf(activity).lastRequestedPermission.requestedPermissions
        )
    }
}
