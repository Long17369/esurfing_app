package com.esurfing.esurfing_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import java.net.Inet4Address
import java.net.InetAddress

/** Process-owned passive observer. All state and channel delivery run on the main looper. */
internal class WifiNetworkMonitor(
    private val context: Context,
    private val hasPermission: () -> Boolean,
) {
    private data class Link(
        var properties: LinkProperties? = null,
        var unblocked: Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q,
    )

    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private val links = mutableMapOf<Network, Link>()
    private val names = mutableMapOf<Network, String>()
    // Match app-usable Wi-Fi, including local-only and captive networks.
    private val request = NetworkRequest.Builder()
        .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
        .build()
    private val linkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = dispatch {
            val link = links.getOrPut(network) { Link() }
            // API 26+ delivers initial link properties immediately after onAvailable.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                link.properties = connectivity?.getLinkProperties(network)
            }
        }

        override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) =
            dispatch { links[network]?.properties = properties }

        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) dispatch {}
        }

        override fun onBlockedStatusChanged(network: Network, blocked: Boolean) =
            dispatch { links[network]?.unblocked = !blocked }

        override fun onLost(network: Network) = dispatch { links.remove(network) }
    }
    private val supported = register(linkCallback)
    private var identityCallback: ConnectivityManager.NetworkCallback? = null
    private var lastSnapshot: Map<String, Any?>? = null
    private var listener: ((Map<String, Any?>) -> Unit)? = null

    init {
        if (supported) {
            // The system-only broadcast also covers location changes with no Activity attached.
            @Suppress("DEPRECATION")
            context.registerReceiver(object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    snapshot()
                }
            }, IntentFilter(LocationManager.MODE_CHANGED_ACTION))
        }
        snapshot()
    }

    fun listen(listener: ((Map<String, Any?>) -> Unit)?) {
        this.listener = null
        if (listener == null) return
        val current = snapshot()
        this.listener = listener
        listener(current)
    }

    fun unvalidatedInternetLink(handle: Long): Network? {
        val manager = connectivity ?: return null
        val (network, link) = links.entries.firstOrNull { it.key.networkHandle == handle }
            ?: return null
        if (!link.unblocked) return null
        val caps = manager.getNetworkCapabilities(network) ?: return null
        return network.takeIf {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        }
    }

    fun requestRevalidation(handle: Long): Boolean {
        val network = unvalidatedInternetLink(handle) ?: return false
        checkNotNull(connectivity).reportNetworkConnectivity(network, true)
        return true
    }

    fun snapshot(forceEvent: Boolean = false): Map<String, Any?> {
        val permissionGranted = hasPermission()
        val canReadSsid = permissionGranted && isLocationEnabled()
        updateIdentityCallback(supported && canReadSsid)
        val legacySsid = if (canReadSsid &&
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S && links.size == 1
        ) {
            legacySsid(links.values.single().properties)
        } else ""

        val current = mapOf(
            "supported" to supported,
            "permissionGranted" to permissionGranted,
            "networks" to links.entries.sortedBy { it.key.networkHandle }.map { (network, link) ->
                val interfaceName = link.properties?.interfaceName.orEmpty()
                val addresses = link.properties?.linkAddresses.orEmpty()
                    .filter { isUsableIpv4(it.address) }
                    .map { mapOf("address" to it.address.hostAddress, "prefixLength" to it.prefixLength) }
                val gateway = link.properties?.routes.orEmpty().asSequence()
                    .filter { it.isDefaultRoute && it.getInterface() == interfaceName }
                    .mapNotNull { it.gateway as? Inet4Address }
                    .firstOrNull { !it.isAnyLocalAddress }
                    ?.hostAddress
                mapOf(
                    "handle" to network.networkHandle,
                    "ssid" to if (canReadSsid) names[network] ?: legacySsid else "",
                    "interfaceName" to interfaceName,
                    "ipv4Addresses" to addresses,
                    "gateway" to gateway,
                    "ready" to (link.unblocked && interfaceName.isNotEmpty() && addresses.isNotEmpty()),
                )
            },
        )
        if (forceEvent || lastSnapshot != current) {
            lastSnapshot = current
            listener?.invoke(current)
        }
        return current
    }

    private fun dispatch(update: () -> Unit) {
        main.post {
            update()
            snapshot()
        }
    }

    private fun register(callback: ConnectivityManager.NetworkCallback): Boolean {
        val manager = connectivity ?: return false
        return try {
            manager.registerNetworkCallback(request, callback)
            true
        } catch (_: RuntimeException) {
            false
        }
    }

    private fun updateIdentityCallback(enabled: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val active = identityCallback
        if (!enabled && active != null) {
            identityCallback = null
            names.clear()
            connectivity?.unregisterNetworkCallback(active)
        } else if (enabled && active == null) {
            // Refresh location-sensitive capabilities independently so permission grants don't
            // clear or re-register the live link observer.
            val next = object : ConnectivityManager.NetworkCallback(
                ConnectivityManager.NetworkCallback.FLAG_INCLUDE_LOCATION_INFO
            ) {
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) =
                    dispatch {
                        if (identityCallback === this) {
                            names[network] = cleanSsid((caps.transportInfo as? WifiInfo)?.ssid)
                        }
                    }

                override fun onLost(network: Network) = dispatch {
                    if (identityCallback === this) names.remove(network)
                }
            }
            if (register(next)) identityCallback = next
        }
    }

    private fun isLocationEnabled(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            context.getSystemService(LocationManager::class.java)?.isLocationEnabled == true
        } else {
            @Suppress("DEPRECATION")
            Settings.Secure.getInt(context.contentResolver, Settings.Secure.LOCATION_MODE, 0) != 0
        }

    @Suppress("DEPRECATION")
    private fun legacySsid(properties: LinkProperties?): String {
        // Pre-31 WifiInfo is global; never attribute it to an ambiguous or mismatched link.
        return try {
            val manager = context.getSystemService(WifiManager::class.java)
            val info = manager?.connectionInfo ?: return ""
            val ip = info.ipAddress
            val matches = properties?.linkAddresses?.any { link ->
                val address = link.address
                isUsableIpv4(address) && address.address.withIndex().all { (index, byte) ->
                    (byte.toInt() and 0xff) == (ip ushr (index * 8) and 0xff)
                }
            } ?: false
            if (matches) cleanSsid(info.ssid) else ""
        } catch (_: SecurityException) {
            ""
        }
    }

    companion object {
        private val emptyHexSsid = Regex("(?i)0x0*")

        private fun isUsableIpv4(address: InetAddress): Boolean =
            address is Inet4Address && !address.isAnyLocalAddress && !address.isLoopbackAddress &&
                !address.isLinkLocalAddress && !address.isMulticastAddress

        internal fun cleanSsid(raw: String?): String {
            val value = raw.orEmpty()
            return if (value.equals(WifiManager.UNKNOWN_SSID, ignoreCase = true) ||
                value == "02:00:00:00:00:00" || value.matches(emptyHexSsid)
            ) "" else value.removeSurrounding("\"")
        }
    }
}
