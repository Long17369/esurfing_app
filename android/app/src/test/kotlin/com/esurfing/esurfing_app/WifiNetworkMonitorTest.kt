package com.esurfing.esurfing_app

import android.app.Application
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.LinkAddress
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.RouteInfo
import android.net.wifi.WifiManager
import android.os.Looper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowNetwork
import org.robolectric.shadows.ShadowNetworkCapabilities
import org.robolectric.util.ReflectionHelpers
import org.robolectric.util.ReflectionHelpers.ClassParameter
import java.net.InetAddress

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class WifiNetworkMonitorTest {
    private val context get() = RuntimeEnvironment.getApplication()
    private val connectivity get() = shadowOf(context.getSystemService(ConnectivityManager::class.java))
    private val wifiInfo get() = requireNotNull(context.getSystemService(WifiManager::class.java)?.connectionInfo)

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    @Suppress("UNCHECKED_CAST")
    private fun Map<String, Any?>.links(): List<Map<String, Any?>> =
        getValue("networks") as List<Map<String, Any?>>

    private fun properties(iface: String?, vararg addresses: String) = LinkProperties().apply {
        interfaceName = iface
        setLinkAddresses(addresses.map { entry ->
            val (address, length) = entry.split("/")
            ReflectionHelpers.callConstructor(
                LinkAddress::class.java,
                ClassParameter.from(InetAddress::class.java, InetAddress.getByName(address)),
                ClassParameter.from(Int::class.javaPrimitiveType!!, length.toInt()),
            )
        })
    }

    private fun ConnectivityManager.NetworkCallback.setLink(
        network: Network,
        properties: LinkProperties,
    ) {
        onLinkPropertiesChanged(network, properties)
        onBlockedStatusChanged(network, false)
        idle()
    }

    private fun route(iface: String, destination: String, prefix: Int, gateway: String): RouteInfo =
        ReflectionHelpers.callConstructor(
            RouteInfo::class.java,
            ClassParameter.from(IpPrefix::class.java, IpPrefix(InetAddress.getByName(destination), prefix)),
            ClassParameter.from(InetAddress::class.java, InetAddress.getByName(gateway)),
            ClassParameter.from(String::class.java, iface),
        )

    @Test
    fun revalidationOnlyTargetsLiveUnvalidatedInternetWifi() {
        val monitor = WifiNetworkMonitor(context) { false }
        val callback = connectivity.networkCallbacks.single()
        val wifi = ShadowNetwork.newInstance(40)
        val caps = ShadowNetworkCapabilities.newInstance()
        shadowOf(caps).addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
        connectivity.setNetworkCapabilities(wifi, caps)
        callback.onAvailable(wifi)
        callback.setLink(wifi, properties("wlan0", "10.0.0.5/24"))
        assertFalse(monitor.requestRevalidation(wifi.networkHandle))

        shadowOf(caps).addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        assertTrue(monitor.requestRevalidation(wifi.networkHandle))
        assertFalse(monitor.requestRevalidation(0L))
        shadowOf(caps).addCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        assertFalse(monitor.requestRevalidation(wifi.networkHandle))
        shadowOf(caps).removeCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        callback.onLost(wifi)
        idle()
        assertFalse(monitor.requestRevalidation(wifi.networkHandle))
    }

    @Test
    fun ipv4WiFiCanBeReadyWithoutValidationOrDefaultRoute() {
        val monitor = WifiNetworkMonitor(context) { false }
        val callback = connectivity.networkCallbacks.single()
        val wifi = ShadowNetwork.newInstance(34)
        val events = mutableListOf<Map<String, Any?>>()
        monitor.listen { events.add(it) }
        assertTrue(events.single().links().isEmpty())

        callback.onAvailable(wifi)
        callback.setLink(wifi, properties("wlan0", "fe80::1/64", "169.254.1.2/16"))
        assertEquals(false, events.last().links().single()["ready"])
        callback.setLink(wifi, properties(null, "10.0.0.5/24"))
        assertEquals(false, events.last().links().single()["ready"])
        callback.setLink(wifi, properties("wlan0", "10.0.0.5/24"))
        val readyLink = events.last().links().single()
        assertEquals(wifi.networkHandle, readyLink["handle"])
        assertEquals("", readyLink["ssid"])
        assertEquals(true, readyLink["ready"])
        assertNull(readyLink["gateway"])
        assertEquals(
            listOf(mapOf("address" to "10.0.0.5", "prefixLength" to 24)),
            readyLink["ipv4Addresses"],
        )
        callback.setLink(wifi, properties("wlan0", "10.0.0.5/24").apply {
            addRoute(route("wlan0", "0.0.0.0", 0, "0.0.0.0"))
        })
        assertNull(events.last().links().single()["gateway"])
        val withGateway = properties("wlan0", "10.0.0.5/24").apply {
            addRoute(route("wlan0", "::", 0, "fe80::1"))
            addRoute(route("wlan0", "10.10.0.0", 16, "10.0.0.2"))
            addRoute(route("wlan0", "0.0.0.0", 0, "10.0.0.1"))
        }
        callback.setLink(wifi, withGateway)
        assertEquals("10.0.0.1", events.last().links().single()["gateway"])
        callback.onBlockedStatusChanged(wifi, true)
        idle()
        assertEquals(false, events.last().links().single()["ready"])
    }

    @Test
    fun handoffRemovesOnlyLostHandleAndUpdatesWhileUnsubscribed() {
        val monitor = WifiNetworkMonitor(context) { false }
        val callback = connectivity.networkCallbacks.single()
        val first = ShadowNetwork.newInstance(35)
        val second = ShadowNetwork.newInstance(36)
        val events = mutableListOf<Map<String, Any?>>()
        monitor.listen { events.add(it) }
        callback.onAvailable(first)
        callback.onAvailable(second)
        callback.setLink(first, properties("wlan0", "10.0.0.5/24"))
        callback.setLink(second, properties("wlan1", "10.0.0.5/24"))
        assertEquals(setOf(first.networkHandle, second.networkHandle),
            events.last().links().map { it["handle"] }.toSet())
        callback.onLost(first)
        callback.onLinkPropertiesChanged(first, properties("wlan0", "10.0.0.5/24"))
        idle()
        assertEquals(second.networkHandle, events.last().links().single()["handle"])

        monitor.listen(null)
        val previousEvents = events.size
        callback.onLost(second)
        idle()
        assertEquals(previousEvents, events.size)
        monitor.listen { events.add(it) }
        assertTrue(events.last().links().isEmpty())
    }

    @Test
    fun ssidPermissionChangesDoNotDropOrMisidentifyActiveLinks() {
        val location = shadowOf(context.getSystemService(LocationManager::class.java))
        location.setLocationEnabled(true)
        var granted = false
        val monitor = WifiNetworkMonitor(context) { granted }
        val linkCallback = connectivity.networkCallbacks.single()
        val wifi = ShadowNetwork.newInstance(37)
        linkCallback.onAvailable(wifi)
        linkCallback.setLink(wifi, properties("wlan0", "10.0.0.5/24"))

        granted = true
        assertEquals("", monitor.snapshot().links().single()["ssid"])
        val identity = connectivity.networkCallbacks.single { it !== linkCallback }
        val caps = ShadowNetworkCapabilities.newInstance()
        val info = wifiInfo
        shadowOf(info).setSSID(" Campus ")
        shadowOf(caps).setTransportInfo(info)
        identity.onCapabilitiesChanged(wifi, caps)
        idle()
        assertEquals(" Campus ", monitor.snapshot().links().single()["ssid"])

        granted = false
        val denied = monitor.snapshot()
        assertFalse(denied["permissionGranted"] as Boolean)
        assertEquals("", denied.links().single()["ssid"])
        assertEquals(true, denied.links().single()["ready"])
        assertEquals(linkCallback, connectivity.networkCallbacks.single())
        identity.onCapabilitiesChanged(wifi, caps)
        idle()
        granted = true
        assertEquals("", monitor.snapshot().links().single()["ssid"])
        assertEquals("", WifiNetworkMonitor.cleanSsid(WifiManager.UNKNOWN_SSID))
    }

    @Test
    @Config(sdk = [30])
    fun legacySsidIsOnlyAttributedToAnUnambiguousMatchingIpv4Link() {
        shadowOf(context.getSystemService(LocationManager::class.java)).setLocationEnabled(true)
        val info = wifiInfo
        shadowOf(info).setInetAddress(InetAddress.getByName("10.0.0.5"))
        shadowOf(info).setSSID("Campus")
        val monitor = WifiNetworkMonitor(context) { true }
        val callback = connectivity.networkCallbacks.single()
        val wifi = ShadowNetwork.newInstance(38)
        callback.onAvailable(wifi)
        callback.setLink(wifi, properties("wlan0", "10.0.0.6/24"))
        assertEquals("", monitor.snapshot().links().single()["ssid"])
        callback.setLink(wifi, properties("wlan0", "10.0.0.5/24"))
        assertEquals("Campus", monitor.snapshot().links().single()["ssid"])
        callback.onAvailable(ShadowNetwork.newInstance(39))
        idle()
        assertTrue(monitor.snapshot().links().all { it["ssid"] == "" })
    }
}
