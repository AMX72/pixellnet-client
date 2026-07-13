package com.hiddify.hiddify

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.telephony.ServiceState
import android.telephony.SignalStrength
import android.telephony.TelephonyManager
import android.util.Base64
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import com.hiddify.hiddify.Application.Companion.packageManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.StandardMethodCodec
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream


class PlatformSettingsHandler : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private lateinit var ignoreRequestResult: MethodChannel.Result

    companion object {
        const val channelName = "com.hiddify.app/platform"

        const val REQUEST_IGNORE_BATTERY_OPTIMIZATIONS = 44

        // v0.1.31: notification для in-app APK download progress.
        // Юзер может свернуть приложение — Android не убьёт download т.к.
        // notification закрепляет процесс в foreground-like state.
        const val UPDATE_NOTIF_CHANNEL_ID = "pixellnet_updater"
        const val UPDATE_NOTIF_ID = 42

        val gson = Gson()

        enum class Trigger(val method: String) {
            IsIgnoringBatteryOptimizations("is_ignoring_battery_optimizations"),
            RequestIgnoreBatteryOptimizations("request_ignore_battery_optimizations"),
            GetInstalledPackages("get_installed_packages"),
            GetPackagesIcon("get_package_icon"),
            CanRequestPackageInstalls("can_request_package_installs"),
            OpenInstallUnknownAppsSettings("open_install_unknown_apps_settings"),
            // v0.1.31: download UI hooks
            DownloadProgressStart("download_progress_start"),
            DownloadProgressUpdate("download_progress_update"),
            DownloadProgressDone("download_progress_done"),
            OemInfo("oem_info"),
            // v0.1.33: cell-tower vs VPN broken diagnostics
            NetworkDiagnostics("network_diagnostics"),
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        val taskQueue = flutterPluginBinding.binaryMessenger.makeBackgroundTaskQueue()
        channel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            channelName,
            StandardMethodCodec.INSTANCE,
            taskQueue
        )
        channel!!.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_IGNORE_BATTERY_OPTIMIZATIONS) {
            ignoreRequestResult.success(resultCode == Activity.RESULT_OK)
            return true
        }
        return false
    }

    data class AppItem(
        @SerializedName("package-name") val packageName: String,
        @SerializedName("name") val name: String,
        @SerializedName("is-system-app") val isSystemApp: Boolean
    )

    @SuppressLint("BatteryLife")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            Trigger.IsIgnoringBatteryOptimizations.method -> {
                result.runCatching {
                    success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            Application.powerManager.isIgnoringBatteryOptimizations(Application.application.packageName)
                        } else {
                            true
                        }
                    )
                }
            }

            Trigger.RequestIgnoreBatteryOptimizations.method -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                    return result.success(true)
                }
                val intent = Intent(
                    android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:${Application.application.packageName}")
                )
                ignoreRequestResult = result
                activity?.startActivityForResult(intent, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            }

            Trigger.CanRequestPackageInstalls.method -> {
                result.runCatching {
                    success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Application.application.packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                    )
                }
            }

            Trigger.OpenInstallUnknownAppsSettings.method -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    return result.success(true)
                }
                runCatching {
                    val intent = Intent(
                        android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${Application.application.packageName}")
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    (activity ?: Application.application).startActivity(intent)
                    result.success(true)
                }.onFailure { result.error("OPEN_SETTINGS_FAILED", it.message, null) }
            }

            Trigger.GetInstalledPackages.method -> {
                GlobalScope.launch {
                    result.runCatching {
                        val flag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            PackageManager.GET_PERMISSIONS or PackageManager.MATCH_UNINSTALLED_PACKAGES
                        } else {
                            @Suppress("DEPRECATION")
                            PackageManager.GET_PERMISSIONS or PackageManager.GET_UNINSTALLED_PACKAGES
                        }
                        val installedPackages =
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                packageManager.getInstalledPackages(
                                    PackageManager.PackageInfoFlags.of(
                                        flag.toLong()
                                    )
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                packageManager.getInstalledPackages(flag)
                            }
                        val list = mutableListOf<AppItem>()
                        installedPackages.forEach {
                            if (it.packageName != Application.application.packageName &&
                                (it.requestedPermissions?.contains(Manifest.permission.INTERNET) == true
                                        || it.packageName == "android")
                            ) {
                                list.add(
                                    AppItem(
                                        it.packageName,
                                        it.applicationInfo?.loadLabel(packageManager).toString(),
                                        (it.applicationInfo?.flags?.and(ApplicationInfo.FLAG_SYSTEM) == 1)
                                    )
                                )
                            }
                        }
                        list.sortBy { it.name }
                        success(gson.toJson(list))
                    }
                }
            }

            Trigger.GetPackagesIcon.method -> {
                result.runCatching {
                    val args = call.arguments as Map<*, *>
                    val packageName =
                        args["packageName"] as String
                    val drawable = packageManager.getApplicationIcon(packageName)
                    val bitmap = Bitmap.createBitmap(
                        drawable.intrinsicWidth,
                        drawable.intrinsicHeight,
                        Bitmap.Config.ARGB_8888
                    )
                    val canvas = Canvas(bitmap)
                    drawable.setBounds(0, 0, canvas.width, canvas.height)
                    drawable.draw(canvas)
                    val byteArrayOutputStream = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream)
                    val base64: String =
                        Base64.encodeToString(byteArrayOutputStream.toByteArray(), Base64.NO_WRAP)
                    success(base64)
                }
            }

            Trigger.DownloadProgressStart.method -> {
                val version = call.argument<String>("version") ?: "?"
                showDownloadNotification(version, 0)
                result.success(true)
            }

            Trigger.DownloadProgressUpdate.method -> {
                val version = call.argument<String>("version") ?: "?"
                val percent = call.argument<Int>("percent") ?: 0
                showDownloadNotification(version, percent)
                result.success(true)
            }

            Trigger.DownloadProgressDone.method -> {
                cancelDownloadNotification()
                result.success(true)
            }

            Trigger.OemInfo.method -> {
                val info = mapOf(
                    "manufacturer" to (Build.MANUFACTURER ?: "").lowercase(),
                    "brand" to (Build.BRAND ?: "").lowercase(),
                    "model" to (Build.MODEL ?: ""),
                    "sdk" to Build.VERSION.SDK_INT,
                )
                result.success(gson.toJson(info))
            }

            Trigger.NetworkDiagnostics.method -> {
                result.success(gson.toJson(collectNetworkDiagnostics()))
            }

            else -> result.notImplemented()
        }
    }

    // v0.1.33: диагностика "нет вышки" vs "VPN сломан". Возвращает enum:
    //   ok — cellular ИЛИ Wi-Fi работает + interfaces up
    //   no_cell_signal — SIM активна, но SERVICE_STATE_OUT_OF_SERVICE
    //                    (оператор выключил вышку — СВО в районе моста/нефтебазы)
    //   cell_signal_but_no_data — вышка есть, packets не идут (VPN сломан ИЛИ
    //                             ISP DPI режет)
    //   wifi_only — только Wi-Fi, cellular не подключен
    //   unknown — permission missing или API error
    //
    // Ключевая тонкость: getActiveNetwork() при поднятом VPN вернёт VPN-сеть.
    // Underlying cellular ищем через cm.allNetworks фильтром по TRANSPORT_CELLULAR
    // && !TRANSPORT_VPN.
    private fun collectNetworkDiagnostics(): Map<String, Any> {
        val ctx = Application.application
        val result = mutableMapOf<String, Any>(
            "state" to "unknown",
            "has_wifi" to false,
            "has_cellular" to false,
            "cellular_has_signal" to false,
            "service_state" to -1,
            "signal_rsrp" to Int.MIN_VALUE,
        )

        try {
            val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return result
            val networks = cm.allNetworks
            var hasWifi = false
            var hasCellular = false
            var cellularValidated = false

            for (n in networks) {
                val caps = cm.getNetworkCapabilities(n) ?: continue
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) hasWifi = true
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
                    hasCellular = true
                    if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) {
                        cellularValidated = true
                    }
                }
            }
            result["has_wifi"] = hasWifi
            result["has_cellular"] = hasCellular

            // Wi-Fi есть — cellular не важно, «нет вышки» не про этот случай
            if (hasWifi) {
                result["state"] = "ok"
                return result
            }

            // Без permission READ_PHONE_STATE — не можем точно сказать про вышку.
            // Fallback на ConnectivityManager: если hasCellular=false и hasWifi=false
            // → скорее всего вышка выключена (или самолётный режим).
            val hasPhonePerm = ctx.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) ==
                    PackageManager.PERMISSION_GRANTED

            if (!hasPhonePerm) {
                result["state"] = when {
                    hasCellular && cellularValidated -> "ok"
                    hasCellular && !cellularValidated -> "cell_signal_but_no_data"
                    else -> "no_cell_signal"
                }
                return result
            }

            // С permission — уточняем через TelephonyManager
            val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                ?: return result
            val ss = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) tm.serviceState else null
            val svcState = ss?.state ?: -1
            result["service_state"] = svcState

            // RSRP только на Android 10+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val sig = tm.signalStrength
                val cellLte = sig?.getCellSignalStrengths(
                    android.telephony.CellSignalStrengthLte::class.java
                )?.firstOrNull()
                val rsrp = cellLte?.rsrp ?: Int.MIN_VALUE
                if (rsrp != Int.MAX_VALUE) {
                    result["signal_rsrp"] = rsrp
                }
                result["cellular_has_signal"] = rsrp != Int.MIN_VALUE &&
                        rsrp != Int.MAX_VALUE && rsrp > -130
            }

            result["state"] = when {
                svcState == ServiceState.STATE_POWER_OFF -> "no_cell_signal"
                svcState == ServiceState.STATE_OUT_OF_SERVICE -> "no_cell_signal"
                svcState == ServiceState.STATE_EMERGENCY_ONLY -> "no_cell_signal"
                hasCellular && cellularValidated -> "ok"
                hasCellular -> "cell_signal_but_no_data"
                else -> "no_cell_signal"
            }
        } catch (e: Exception) {
            result["error"] = e.message ?: "unknown"
        }
        return result
    }

    // v0.1.31: notification helpers — простой прогресс-бар для download.
    // POST_NOTIFICATIONS permission на Android 13+ может отсутствовать — тогда
    // silently skip (не критично, скачивание всё равно идёт).
    private fun ensureNotifChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = ctx.getSystemService(NotificationManager::class.java)
            if (nm?.getNotificationChannel(UPDATE_NOTIF_CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    UPDATE_NOTIF_CHANNEL_ID,
                    "PIXELLNET Обновление",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Прогресс скачивания новой версии"
                    setShowBadge(false)
                }
                nm?.createNotificationChannel(ch)
            }
        }
    }

    private fun showDownloadNotification(version: String, percent: Int) {
        val ctx = Application.application
        ensureNotifChannel(ctx)
        val builder = NotificationCompat.Builder(ctx, UPDATE_NOTIF_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Скачиваем PIXELLNET $version")
            .setContentText(if (percent > 0) "$percent%" else "Подключаемся...")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setProgress(100, percent.coerceIn(0, 100), percent <= 0)
        runCatching {
            NotificationManagerCompat.from(ctx).notify(UPDATE_NOTIF_ID, builder.build())
        }
    }

    private fun cancelDownloadNotification() {
        runCatching {
            NotificationManagerCompat.from(Application.application).cancel(UPDATE_NOTIF_ID)
        }
    }
}