package com.hiddify.hiddify.bg

import android.annotation.TargetApi
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import com.hiddify.hiddify.Application
import com.hiddify.hiddify.Settings
import com.hiddify.core.mobile.Mobile
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.ObsoleteCoroutinesApi
import kotlinx.coroutines.channels.actor
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import java.net.UnknownHostException
import java.util.concurrent.atomic.AtomicBoolean


object DefaultNetworkListener {
    private const val TAG = "DefaultNetworkListener"
    private val verbose get() = Settings.verboseLogging

    // WakeLock held for HANDOVER_WAKELOCK_MS after IP change so CPU doesn't sleep
    // while sing-box re-evaluates outbound and completes fresh TLS handshake.
    private const val HANDOVER_WAKELOCK_MS = 8_000L
    private var handoverWakeLock: PowerManager.WakeLock? = null

    // True when we lost a network and are waiting for a new one (airplane mode / WiFi→Cell).
    // Guards against calling Mobile.wake() on stale actors after VPN revoke.
    private val isReconnecting = AtomicBoolean(false)

    // Set by BoxService to prevent Mobile.wake() being called after service tear-down.
    // BoxService.onStartCommand → true; BoxService.stopService (before Mobile.close) → false.
    var serviceActive = AtomicBoolean(false)

    private sealed class NetworkMessage {
        class Start(val key: Any, val listener: (Network?) -> Unit) : NetworkMessage()

        class Get : NetworkMessage() {
            val response = CompletableDeferred<Network>()
        }

        class Stop(val key: Any) : NetworkMessage()

        class Put(val network: Network) : NetworkMessage()

        class Update(val network: Network) : NetworkMessage()

        class Lost(val network: Network) : NetworkMessage()

        // Fired on CGNAT/BS handoff: same Network object, IP changed in LinkProperties.
        // Triggers Mobile.wake() to force sing-box outbound re-evaluation immediately.
        class WarmupReconnect(val network: Network) : NetworkMessage()
    }

    @OptIn(DelicateCoroutinesApi::class, ObsoleteCoroutinesApi::class)
    private val networkActor =
        GlobalScope.actor<NetworkMessage>(Dispatchers.Unconfined) {
            val listeners = mutableMapOf<Any, (Network?) -> Unit>()
            var network: Network? = null
            val pendingRequests = arrayListOf<NetworkMessage.Get>()
            for (message in channel) {
                when (message) {
                    is NetworkMessage.Start -> {
                        if (listeners.isEmpty()) register()
                        listeners[message.key] = message.listener
                        if (network != null) message.listener(network)
                    }

                    is NetworkMessage.Get -> {
                        check(listeners.isNotEmpty()) { "Getting network without any listeners is not supported" }
                        if (network == null) {
                            pendingRequests += message
                        } else {
                            message.response.complete(
                                network,
                            )
                        }
                    }

                    is NetworkMessage.Stop ->
                        if (listeners.isNotEmpty() &&
                            // was not empty
                            listeners.remove(message.key) != null &&
                            listeners.isEmpty()
                        ) {
                            network = null
                            unregister()
                        }

                    is NetworkMessage.Put -> {
                        val wasReconnecting = isReconnecting.getAndSet(false)
                        network = message.network
                        if (verbose) Log.d(TAG, "onAvailable — network=${message.network} wasReconnecting=$wasReconnecting serviceActive=${serviceActive.get()} listeners=${listeners.size}")
                        pendingRequests.forEach { it.response.complete(message.network) }
                        pendingRequests.clear()
                        listeners.values.forEach { it(network) }
                        // If we lost a previous network (airplane off, WiFi→Cell transition),
                        // sing-box may be holding dead sockets. Force outbound re-evaluation
                        // and acquire WakeLock so CPU stays awake during TLS re-handshake.
                        if (wasReconnecting && serviceActive.get()) {
                            GlobalScope.launch(Dispatchers.IO) {
                                // Double-check after dispatch — service may have stopped
                                // between the Put processing and coroutine execution.
                                if (!serviceActive.get()) return@launch
                                try {
                                    Mobile.wake()
                                    Log.d(TAG, "Put/NetworkTransition: Mobile.wake() called after network switch")
                                } catch (e: Exception) {
                                    Log.w(TAG, "Put/NetworkTransition: Mobile.wake() failed: ${e.message}")
                                }
                            }
                            acquireHandoverWakeLock()
                        }
                    }

                    is NetworkMessage.Update ->
                        if (network == message.network) {
                            listeners.values.forEach {
                                it(
                                    network,
                                )
                            }
                        }

                    is NetworkMessage.Lost ->
                        if (network == message.network) {
                            // Mark reconnecting BEFORE notifying listeners so that if
                            // onAvailable fires synchronously on the same thread, wasReconnecting
                            // is already true when Put is processed.
                            isReconnecting.set(true)
                            network = null
                            listeners.values.forEach { it(null) }
                            Log.d(TAG, "Lost default network — reconnecting=true, waiting for onAvailable")
                            if (verbose) Log.d(TAG, "onLost — network=${message.network} serviceActive=${serviceActive.get()} listeners=${listeners.size}")
                        }

                    is NetworkMessage.WarmupReconnect -> {
                        // IP changed on same Network (BS handoff / CGNAT reassign).
                        // 1. Notify listeners so sing-box rebinds interface immediately.
                        if (network == message.network) {
                            listeners.values.forEach { it(network) }
                        }
                        // 2. Wake sing-box so urltest selector re-evaluates outbounds NOW
                        //    instead of waiting for the next 10s interval.
                        if (serviceActive.get()) GlobalScope.launch(Dispatchers.IO) {
                            if (!serviceActive.get()) return@launch
                            try {
                                Mobile.wake()
                                Log.d(TAG, "WarmupReconnect: Mobile.wake() called after IP change")
                            } catch (e: Exception) {
                                Log.w(TAG, "WarmupReconnect: Mobile.wake() failed: ${e.message}")
                            }
                        }
                        // 3. Acquire partial WakeLock so CPU doesn't sleep during handshake.
                        acquireHandoverWakeLock()
                    }
                }
            }
        }

    suspend fun start(key: Any, listener: (Network?) -> Unit) = networkActor.send(
        NetworkMessage.Start(
            key,
            listener,
        ),
    )

    suspend fun get(): Network = if (fallback) {
        @TargetApi(23)
        Application.connectivity.activeNetwork
            ?: error("missing default network") // failed to listen, return current if available
    } else {
        NetworkMessage.Get().run {
            networkActor.send(this)
            response.await()
        }
    }

    suspend fun stop(key: Any) = networkActor.send(NetworkMessage.Stop(key))

    // NB: this runs in ConnectivityThread, and this behavior cannot be changed until API 26
    private object Callback : ConnectivityManager.NetworkCallback() {
        // Track last known link addresses per network to detect CGNAT IP change (BS handoff).
        // onLost is NOT called when the carrier reassigns IP — only onLinkPropertiesChanged fires.
        private val lastLinkAddresses = mutableMapOf<Network, Set<String>>()

        override fun onAvailable(network: Network) = runBlocking {
            networkActor.send(
                NetworkMessage.Put(
                    network,
                ),
            )
        }

        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
            // it's a good idea to refresh capabilities
            runBlocking { networkActor.send(NetworkMessage.Update(network)) }
        }

        override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
            // Detect CGNAT IP change: same Network object, different LinkAddresses.
            // This fires on BS handoff without onLost/onAvailable cycle.
            val currentAddresses = linkProperties.linkAddresses.map { it.address.hostAddress }.toSet()
            val previous = lastLinkAddresses[network]
            if (verbose) Log.d(TAG, "onLinkPropertiesChanged — network=$network dns=${linkProperties.dnsServers} addresses=$currentAddresses previous=$previous")
            if (previous != null && previous != currentAddresses) {
                Log.d(TAG, "IP change detected on BS handoff: $previous -> $currentAddresses")
                // WarmupReconnect: notify listeners + Mobile.wake() + WakeLock.
                // Replaces plain Update() which only notified listeners without waking sing-box.
                runBlocking { networkActor.send(NetworkMessage.WarmupReconnect(network)) }
            }
            lastLinkAddresses[network] = currentAddresses
        }

        override fun onLost(network: Network) = runBlocking {
            lastLinkAddresses.remove(network)
            networkActor.send(
                NetworkMessage.Lost(
                    network,
                ),
            )
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    private fun acquireHandoverWakeLock() {
        // Release any existing lock first (edge case: two rapid handoffs).
        handoverWakeLock?.release()
        handoverWakeLock = null
        val pm = Application.application.getSystemService(android.content.Context.POWER_SERVICE) as? PowerManager
            ?: return
        val wl = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "pixellnet:handover"
        ).also {
            it.setReferenceCounted(false)
            it.acquire(HANDOVER_WAKELOCK_MS)
        }
        handoverWakeLock = wl
        Log.d(TAG, "Handover WakeLock acquired for ${HANDOVER_WAKELOCK_MS}ms")
        // Auto-release after timeout (acquire(timeout) already does this, but keep reference clean).
        GlobalScope.launch(Dispatchers.IO) {
            kotlinx.coroutines.delay(HANDOVER_WAKELOCK_MS + 500)
            handoverWakeLock = null
        }
    }

    private var fallback = false
    private val request =
        NetworkRequest.Builder().apply {
            addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
            if (Build.VERSION.SDK_INT == 23) { // workarounds for OEM bugs
                removeCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                removeCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL)
            }
        }.build()
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Unfortunately registerDefaultNetworkCallback is going to return VPN interface since Android P DP1:
     * https://android.googlesource.com/platform/frameworks/base/+/dda156ab0c5d66ad82bdcf76cda07cbc0a9c8a2e
     *
     * This makes doing a requestNetwork with REQUEST necessary so that we don't get ALL possible networks that
     * satisfies default network capabilities but only THE default network. Unfortunately, we need to have
     * android.permission.CHANGE_NETWORK_STATE to be able to call requestNetwork.
     *
     * Source: https://android.googlesource.com/platform/frameworks/base/+/2df4c7d/services/core/java/com/android/server/ConnectivityService.java#887
     */
    private fun register() {
        when (Build.VERSION.SDK_INT) {
            in 31..Int.MAX_VALUE ->
                @TargetApi(31)
                {
                    Application.connectivity.registerBestMatchingNetworkCallback(
                        request,
                        Callback,
                        mainHandler,
                    )
                }

            in 28 until 31 ->
                @TargetApi(28)
                { // we want REQUEST here instead of LISTEN
                    Application.connectivity.requestNetwork(request, Callback, mainHandler)
                }

            in 26 until 28 ->
                @TargetApi(26)
                {
                    Application.connectivity.registerDefaultNetworkCallback(Callback, mainHandler)
                }

            in 24 until 26 ->
                @TargetApi(24)
                {
                    Application.connectivity.registerDefaultNetworkCallback(Callback)
                }

            else ->
                try {
                    fallback = false
                    Application.connectivity.requestNetwork(request, Callback)
                } catch (e: RuntimeException) {
                    fallback =
                        true // known bug on API 23: https://stackoverflow.com/a/33509180/2245107
                }
        }
    }

    private fun unregister() {
        runCatching {
            Application.connectivity.unregisterNetworkCallback(Callback)
        }
    }
}