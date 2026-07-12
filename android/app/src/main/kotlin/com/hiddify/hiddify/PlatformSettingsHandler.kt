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
import android.net.Uri
import android.os.Build
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

            else -> result.notImplemented()
        }
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