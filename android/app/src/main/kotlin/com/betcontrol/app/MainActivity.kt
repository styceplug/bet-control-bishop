package com.betcontrol.app

import android.app.Activity
import android.app.NotificationManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import com.judemanutd.autostarter.AutoStartPermissionHelper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.betcontrol/blocker"
    private val VPN_REQUEST_CODE = 100
    private val DEVICE_ADMIN_REQUEST_CODE = 101
    private val BATTERY_OPTIMIZATION_REQUEST_CODE = 102

    private lateinit var devicePolicyManager: DevicePolicyManager
    private lateinit var adminComponent: ComponentName

    private var pendingRestorationFlag = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        devicePolicyManager =
            getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        adminComponent = ComponentName(this, BetControlDeviceAdmin::class.java)

        requestBatteryOptimizationExemption()
        handleVpnPermissionRequest(intent)

        if (intent?.getBooleanExtra("show_protection_restoration", false) == true) {
            pendingRestorationFlag = true
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleVpnPermissionRequest(intent)

        if (intent.getBooleanExtra("show_protection_restoration", false)) {
            pendingRestorationFlag = true
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod(
                    "showProtectionRestoration", null
                )
            }
        }
    }

    private fun handleVpnPermissionRequest(intent: Intent?) {
        if (intent?.getBooleanExtra("request_vpn_permission", false) != true) return
        val vpnIntent = VpnService.prepare(this)
        if (vpnIntent != null) {
            startActivityForResult(vpnIntent, VPN_REQUEST_CODE)
        } else {
            startForegroundService(
                Intent(this, BetControlVpnService::class.java).apply { action = "START" }
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {

                "startVpn" -> {
                    ProtectionStateStore.syncFromFlutterPrefs(this)
                    val vpnIntent = VpnService.prepare(this)
                    if (vpnIntent != null) {
                        startActivityForResult(vpnIntent, VPN_REQUEST_CODE)
                        result.success("requesting_permission")
                    } else {
                        startForegroundService(
                            Intent(this, BetControlVpnService::class.java).apply {
                                action = "START"
                            }
                        )
                        result.success("started")
                    }
                }

                "isVpnPermissionGranted" -> {
                    result.success(VpnService.prepare(this) == null)
                }

                "requestVpnPermission" -> {
                    val vpnIntent = VpnService.prepare(this)
                    if (vpnIntent != null) {
                        startActivityForResult(vpnIntent, VPN_REQUEST_CODE)
                        result.success("requesting_permission")
                    } else {
                        result.success("already_granted")
                    }
                }

                "stopVpn" -> {
                    ProtectionStateStore.clear(this)
                    BootReceiver().cancelExpiryAlarm(this)
                    startService(
                        Intent(this, BetControlVpnService::class.java).apply {
                            action = "STOP"
                        }
                    )
                    result.success("stopped")
                }

                "hasConflictingVpn" -> result.success(hasConflictingVpn())

                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success("opened")
                }

                "openAlwaysOnVpnSettings" -> {
                    startActivity(Intent(Settings.ACTION_VPN_SETTINGS))
                    result.success("opened")
                }

                "isAlwaysOnVpnEnabled" -> {
                    result.success(isAlwaysOnVpnEnabled())
                }

                "openVpnSettings" -> {
                    startActivity(Intent(Settings.ACTION_VPN_SETTINGS))
                    result.success("opened")
                }

                "isAccessibilityEnabled" -> {
                    result.success(isAccessibilityServiceEnabled())
                }

                "requestDeviceAdmin" -> {
                    if (!devicePolicyManager.isAdminActive(adminComponent)) {
                        val intent =
                            Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                                putExtra(
                                    DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                                    adminComponent
                                )
                                putExtra(
                                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                    "BetControl needs device admin to prevent " +
                                            "uninstall while blocking is active."
                                )
                            }
                        startActivityForResult(intent, DEVICE_ADMIN_REQUEST_CODE)
                        result.success("requesting")
                    } else {
                        result.success("already_active")
                    }
                }

                "isDeviceAdminActive" -> {
                    result.success(devicePolicyManager.isAdminActive(adminComponent))
                }

                "isBatteryOptimizationExempt" -> {
                    result.success(isBatteryOptimizationExempt())
                }

                "requestBatteryOptimizationExemption" -> {
                    requestBatteryOptimizationExemption()
                    result.success(null)
                }

                "isPowerSaveModeOn" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isPowerSaveMode)
                }

                "getManufacturer" -> {
                    result.success(Build.MANUFACTURER)
                }

                "openAutoStartSettings" -> {
                    // Try OEM-specific auto-start screen first.
                    // Falls back to app details screen (where user can manage battery
                    // restrictions manually) — NOT the generic battery settings page.
                    val opened = tryOpenAutoStartSettings()
                    if (!opened) {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.parse("package:$packageName")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                            )
                        } catch (e: Exception) {
                            startActivity(Intent(Settings.ACTION_SETTINGS))
                        }
                    }
                    result.success(null)
                }

                "syncBlockState" -> {
                    val isBlocking = call.argument<Boolean>("isBlocking") ?: false
                    val unlockTime = call.argument<Long>("unlockTime") ?: 0L
                    ProtectionStateStore.write(this, isBlocking, unlockTime)

                    val prefsEditor = getSharedPreferences(
                        "FlutterSharedPreferences", MODE_PRIVATE
                    ).edit()
                    if (isBlocking) {
                        prefsEditor.putLong(
                            "flutter.block_activated_at",
                            System.currentTimeMillis()
                        )
                        if (unlockTime > 0L) {
                            BootReceiver().scheduleExpiryAlarm(this, unlockTime)
                        }
                    } else {
                        prefsEditor.remove("flutter.block_activated_at")
                        BootReceiver().cancelExpiryAlarm(this)
                    }
                    prefsEditor.apply()

                    result.success(null)
                }

                "clearRestorationNotification" -> {
                    clearRestorationNotification()
                    result.success(null)
                }

                "checkRestorationFlag" -> {
                    val flag = pendingRestorationFlag
                    pendingRestorationFlag = false
                    result.success(flag)
                }

                "getNativeUnlockTime" -> {
                    val state = ProtectionStateStore.read(this)
                    result.success(if (state.unlockTime > 0L) state.unlockTime else null)
                }

                else -> result.notImplemented()
            }
        }
        
          // ── Timezone channel ─────────────────────────────────────────────
        val tzChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.betcontrol/timezone"
        )
        tzChannel.setMethodCallHandler { call, result ->
            if (call.method == "getTimezoneName") {
                result.success(java.util.TimeZone.getDefault().id)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun tryOpenAutoStartSettings(): Boolean {
        // Try confirmed Infinix/Tecno/Itel class first (verified via pm dump)
        val manufacturer = Build.MANUFACTURER.lowercase()
        if (manufacturer.contains("infinix") ||
            manufacturer.contains("tecno") ||
            manufacturer.contains("itel")) {
            try {
                startActivity(Intent().apply {
                    setClassName(
                        "com.transsion.phonemaster",
                        "com.cyin.himgr.autostart.AutoStartActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
                return true
            } catch (e: Exception) {
                // fall through to library
            }
        }
        // All other OEMs — use AutoStarter library
        return try {
            AutoStartPermissionHelper.getInstance()
                .getAutoStartPermission(this, open = true, newTask = true)
        } catch (e: Exception) {
            false
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            VPN_REQUEST_CODE -> {
                if (resultCode == Activity.RESULT_OK) {
                    if (ProtectionStateStore.read(this).isActive) {
                        startForegroundService(
                            Intent(this, BetControlVpnService::class.java).apply {
                                action = "START"
                            }
                        )
                    }
                } else {
                    getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                        .edit()
                        .putBoolean("flutter.vpn_interrupted", true)
                        .apply()
                }
            }
        }
    }

    private fun isBatteryOptimizationExempt(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (isBatteryOptimizationExempt()) return
        try {
            startActivityForResult(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                },
                BATTERY_OPTIMIZATION_REQUEST_CODE
            )
        } catch (e: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (ex: Exception) {
                ex.printStackTrace()
            }
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val expectedComponent =
            ComponentName(this, BetControlAccessibilityService::class.java)
        val shortName = "${packageName}/.BetControlAccessibilityService"
        val fullName =
            "${packageName}/${BetControlAccessibilityService::class.java.name}"

        return enabled.split(":").any { s ->
            ComponentName.unflattenFromString(s) == expectedComponent ||
                    s == shortName || s == fullName
        }
    }

    private fun hasConflictingVpn(): Boolean {
        val prefs =
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (prefs.getBoolean("flutter.vpn_running", false)) return false
        if (isAlwaysOnVpnEnabled()) return false

        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        return cm.allNetworks.any { network ->
            cm.getNetworkCapabilities(network)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        }
    }

    private fun isAlwaysOnVpnEnabled(): Boolean {
        val prefs =
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getBoolean("flutter.always_on_vpn_confirmed", false)
    }

    private fun clearRestorationNotification() {
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(9001)
    }
}