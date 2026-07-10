package com.hiddify.hiddify.bg

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.MutableLiveData
import com.hiddify.hiddify.Application
import com.hiddify.hiddify.R
import com.hiddify.hiddify.Settings
import com.hiddify.hiddify.constant.Action
import com.hiddify.hiddify.constant.Alert
import com.hiddify.hiddify.constant.Status
import com.hiddify.core.mobile.SetupOptions

import go.Seq
import com.hiddify.core.libbox.Libbox
import com.hiddify.core.mobile.Mobile


import com.hiddify.core.libbox.CommandServer
import com.hiddify.core.libbox.CommandServerHandler
import com.hiddify.core.libbox.Notification
import com.hiddify.core.libbox.PlatformInterface
import com.hiddify.core.libbox.SystemProxyStatus
import com.hiddify.hiddify.BuildConfig
import com.hiddify.hiddify.MainActivity
import com.hiddify.hiddify.constant.Bugs
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.io.File

class BoxService(
        private val service: Service,
        private val platformInterface: PlatformInterface
)  {

    companion object {
        private const val TAG = "A/BoxService"

        private var initializeOnce = false
        private lateinit var workingDir: File
        private fun initialize() {
            System.setProperty("GODEBUG", "efence=1,stacktraceback=2");
            System.setProperty("GOGC", "off");
            if (initializeOnce) return
            val baseDir = Application.application.filesDir

            baseDir.mkdirs()
            workingDir = Application.application.getExternalFilesDir(null) ?: return
            workingDir.mkdirs()
            val tempDir = Application.application.cacheDir
            tempDir.mkdirs()
            Log.d(TAG, "base dir: ${baseDir.path}")
            Log.d(TAG, "working dir: ${workingDir.path}")
            Log.d(TAG, "temp dir: ${tempDir.path}")

//
            //Mobile.setup(baseDir.path, workingDir.path, tempDir.path,  2L ,"127.0.0.1:{Setting}","",false,this)
//            Libbox.setup(baseDir.path, workingDir.path, tempDir.path, false)

//            Libbox.setup(SetupOptions().also {
//                it.basePath = baseDir.path
//                it.workingPath = workingDir.path
//                it.tempPath = tempDir.path
//                it.fixAndroidStack = Bugs.fixAndroidStack
//
//            })
            Libbox.redirectStderr(File(Settings.workingDir, "stderr.log").path)
            initializeOnce = true
            return
        }

        fun start() {
            val intent = runBlocking {
                withContext(Dispatchers.IO) {
                    Intent(Application.application, Settings.serviceClass())
                }
            }
            ContextCompat.startForegroundService(Application.application, intent)
        }

        fun stop() {
            Application.application.sendBroadcast(
                    Intent(Action.SERVICE_CLOSE).setPackage(
                            Application.application.packageName
                    )
            )
        }


    }

    var fileDescriptor: ParcelFileDescriptor? = null

    // HIGH_PERF WifiLock keeps radio in full-power mode, preventing 300-500ms radio
    // wake latency when a packet arrives after the radio dozed between BS handoffs.
    @Suppress("DEPRECATION")
    private val wifiLock: WifiManager.WifiLock? by lazy {
        runCatching {
            Application.wifiManager.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "pixellnet:vpn_wifi"
            )
        }.getOrNull()
    }

    private val status = MutableLiveData(Status.Stopped)
    private val binder = ServiceBinder(status)
    private val notification = ServiceNotification(status, service)
//    private var boxService: BoxService? = null
    private var commandServer: CommandServer? = null
    private var receiverRegistered = false
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Action.SERVICE_CLOSE -> {
                    stopService()
                }

                PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        serviceUpdateIdleMode()
                    }
                }
            }
        }
    }
    


    private val verbose get() = Settings.verboseLogging

    private var activeProfileName = ""
    private suspend fun startService() {
        try {
            status.postValue(Status.Starting)
            Log.d(TAG, "starting service")
            if (verbose) Log.d(TAG, "startService() — activeConfigPath=${Settings.activeConfigPath} profileName=${Settings.activeProfileName} debugMode=${Settings.debugMode}")
            withContext(Dispatchers.Main) {
                notification.show(activeProfileName, R.string.status_starting)
            }

            val selectedConfigPath = Settings.activeConfigPath
            if (selectedConfigPath.isBlank()) {
                stopAndAlert(Alert.EmptyConfiguration)
                return
            }

            activeProfileName = Settings.activeProfileName

            withContext(Dispatchers.Main) {
                notification.show(activeProfileName, R.string.status_starting)
                binder.broadcast {
                    it.onServiceResetLogs(listOf())
                }
            }

            DefaultNetworkMonitor.start()
            // Subscribe to network loss/restore for notification updates.
            // Key "box_notification" is separate from DefaultNetworkMonitor's key.
            DefaultNetworkListener.start("box_notification") { network ->
                if (status.value == Status.Started || status.value == Status.Starting) {
                    GlobalScope.launch(Dispatchers.Main) {
                        if (network == null) {
                            notification.show(activeProfileName, R.string.status_reconnecting)
                        } else {
                            notification.show(activeProfileName, R.string.status_started)
                        }
                    }
                }
            }
            Libbox.setMemoryLimit(!Settings.disableMemoryLimit)
            // v0.0.35 CRITICAL FIX (verified через adb logcat):
            // Alert.CreateService message="port 17078 is already in use" — коллизия
            // с Flutter's Mobile.setup(port=17078) из Trigger.Setup. Design upstream
            // Hiddify: portFront=17078 для Flutter monitoring, portBack=17079 для VPN
            // tunnel. Раньше BoxService использовал Settings.grpcServiceModePort который
            // Trigger.Start должен был обновить до 17079, но по timing race это
            // происходило не всегда (или Setup перезаписывал обратно на 17078).
            // Hardcoded 17079 = никакой race conditions.
            val backendPort = 17079
            if (verbose) Log.d(TAG, "Mobile.setup() — mode=4 listen=127.0.0.1:$backendPort debug=${Settings.debugMode} fixAndroidStack=${com.hiddify.hiddify.bg.Bugs.fixAndroidStack}")
            val newService = try {
                Mobile.setup(
                    SetupOptions().also {
                        it.basePath = Settings.baseDir
                        it.workingDir = Settings.workingDir
                        it.tempDir = Settings.tempDir
                        it.fixAndroidStack = com.hiddify.hiddify.bg.Bugs.fixAndroidStack
                        it.mode=4L
                        it.listen= "127.0.0.1:$backendPort"
                        it.secret=""
                        it.debug = Settings.debugMode
                    },platformInterface)
            } catch (e: Exception) {
                stopAndAlert(Alert.CreateService, e.message)
                return
            }
            if (verbose) Log.d(TAG, "Mobile.setup() returned — status→Started")
            status.postValue(Status.Started)

            if (Settings.startCoreAfterStartingService){
                if (verbose) Log.d(TAG, "Mobile.start() — startCoreAfterStartingService=true")
                Mobile.start("","")
                }
//            if (delayStart) {
//                delay(1000L)
//            }

//            newService.start()
//            boxService = newService
//            commandServer?.setService(boxService)


            // Acquire HIGH_PERF WifiLock: keeps WiFi radio active during BS handoff,
            // eliminates 300-500ms radio wake-up penalty on first packet after handover.
            wifiLock?.let { if (!it.isHeld) it.acquire() }

            withContext(Dispatchers.Main) {
                notification.show(activeProfileName, R.string.status_started)
            }
            notification.start()
        } catch (e: Exception) {
            stopAndAlert(Alert.StartService, e.message)
            return
        }
    }

    fun serviceReload() {
        runBlocking {
            serviceReload0()
        }
    }

    suspend fun serviceReload0() {
        notification.close()
        status.postValue(Status.Starting)

        val pfd = fileDescriptor
        if (pfd != null) {
            pfd.close()
            fileDescriptor = null
        }
        
//        boxService?.apply {
//            runCatching {
//                close()
//            }.onFailure {
//                writeLog("service: error when closing: $it")
//            }
//            Seq.destroyRef(refnum)
//        }
        Mobile.stop()
//        boxService = null
        
            startService()
        
    }

    fun getSystemProxyStatus(): SystemProxyStatus {
        val status = SystemProxyStatus()
        if (service is VPNService) {
            status.available = service.systemProxyAvailable
            status.enabled = service.systemProxyEnabled
        }
        return status
    }

    fun setSystemProxyEnabled(isEnabled: Boolean) {
        serviceReload()
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun serviceUpdateIdleMode() {
        if (Application.powerManager.isDeviceIdleMode) {
//            boxService?.pause()
            //Mobile.pause()
        } else {
            Mobile.wake()
//            boxService?.wake()
        }
    }

    private fun stopService() {
        if (status.value == Status.Stopped) return
        if (verbose) Log.d(TAG, "stopService() — current status=${status.value}")
        // Signal before any async work so Mobile.wake() guards in DefaultNetworkListener
        // see the false value and skip wake calls during tear-down.
        DefaultNetworkListener.serviceActive.set(false)
        status.value = Status.Stopping
        if (receiverRegistered) {
            service.unregisterReceiver(receiver)
            receiverRegistered = false
        }
        notification.close()
        // Run cleanup synchronously via runBlocking to guarantee Mobile.close(4L)
        // completes before any subsequent startService() attempts Mobile.setup().
        // Prevents "createService - null" on rapid restart after network change.
        runBlocking(Dispatchers.IO) {
            val pfd = fileDescriptor
            if (pfd != null) {
                runCatching { pfd.close() }
                fileDescriptor = null
            }
            runCatching { DefaultNetworkListener.stop("box_notification") }
            runCatching { DefaultNetworkMonitor.stop() }
            wifiLock?.let { if (it.isHeld) runCatching { it.release() } }
            Settings.startedByUser = false
            runCatching { Mobile.close(4L) }
            if (verbose) Log.d(TAG, "Mobile.close(4L) complete — status→Stopped")
        }
        status.value = Status.Stopped
        service.stopSelf()
        notification.close()
    }

    private suspend fun stopAndAlert(type: Alert, message: String? = null) {
        Settings.startedByUser = false
        withContext(Dispatchers.Main) {
            if (receiverRegistered) {
                service.unregisterReceiver(receiver)
                receiverRegistered = false
            }
            notification.close()
            binder.broadcast { callback ->
                callback.onServiceAlert(type.ordinal, message)
            }
            status.value = Status.Stopped
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    @Suppress("SameReturnValue")
    internal fun onStartCommand(): Int {
        if (verbose) Log.d(TAG, "onStartCommand() — status=${status.value}")
        // HIGH FIX (Android audit): также блокируем при Stopping чтобы не
        // допустить второй Mobile.setup пока идёт runBlocking { Mobile.close }
        if (status.value == Status.Starting || status.value == Status.Stopping) {
            if (verbose) Log.d(TAG, "onStartCommand() ignored — already ${status.value}")
            return Service.START_STICKY
        }
        if (status.value != Status.Stopped) return Service.START_STICKY
        status.value = Status.Starting

        if (!receiverRegistered) {
            ContextCompat.registerReceiver(service, receiver, IntentFilter().apply {
                addAction(Action.SERVICE_CLOSE)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
                }
            }, ContextCompat.RECEIVER_NOT_EXPORTED)
            receiverRegistered = true
        }

        // NOTE: убран автоматический запрос REQUEST_IGNORE_BATTERY_OPTIMIZATIONS —
        // MIUI/Xiaomi перехватывает этот intent и показывает свой экран «Контроль
        // фоновой активности», что путает юзера. Battery optimization exemption теперь
        // запрашивается через Настройки в Flutter слое (PlatformSettingsHandler),
        // только по явному действию юзера, с объяснением зачем.

        DefaultNetworkListener.serviceActive.set(true)
        GlobalScope.launch(Dispatchers.IO) {
            Settings.startedByUser = true
            initialize()
//            try {
//                startCommandServer()
//            } catch (e: Exception) {
//                stopAndAlert(Alert.StartCommandServer, e.message)
//                return@launch
//            }
            startService()
        }
        return Service.START_STICKY
    }

    fun onBind(intent: Intent): IBinder {
        return binder
    }

    fun onDestroy() {
        binder.close()
    }

    fun onRevoke() {
        if (verbose) Log.d(TAG, "onRevoke() — VPN permission revoked by system or another VPN app")
        stopService()
    }

    internal fun sendNotification(notification: Notification) {
        return
        val builder =
            NotificationCompat.Builder(service, notification.identifier).setShowWhen(false)
                .setContentTitle(notification.title).setContentText(notification.body)
                .setOnlyAlertOnce(true).setSmallIcon(R.drawable.ic_launcher_foreground)
                .setCategory(NotificationCompat.CATEGORY_EVENT)
                .setPriority(NotificationCompat.PRIORITY_HIGH).setAutoCancel(true)
        if (!notification.subtitle.isNullOrBlank()) {
            builder.setContentInfo(notification.subtitle)
        }
        if (!notification.openURL.isNullOrBlank()) {
            builder.setContentIntent(
                PendingIntent.getActivity(
                    service,
                    0,
                    Intent(
                        service,
                        MainActivity::class.java,
                    ).apply {
                        setAction(Action.SERVICE).setData(Uri.parse(notification.openURL))
                        setFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    },
                    ServiceNotification.flags,
                ),
            )
        }
        GlobalScope.launch(Dispatchers.Main) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Application.notification.createNotificationChannel(
                    NotificationChannel(
                        notification.identifier,
                        notification.typeName,
                        NotificationManager.IMPORTANCE_HIGH,
                    ),
                )
            }
            Application.notification.notify(notification.typeID, builder.build())
        }
    }

     fun writeDebugMessage(message: String?) {
        Log.d("BoxService", message!!)
        binder.broadcast {
            it.onServiceWriteLog(message)
        }
    }

}