package com.betcontrol.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent

class BetControlAccessibilityService : AccessibilityService() {

    private val handler = Handler(Looper.getMainLooper())
    private var lastSentHome = 0L
    private var serviceStartTime = 0L

    private val aggressiveWindowMs = 10_000L
    private val vpnSettingsGraceMs = 60_000L

    private val PREFS_NAME = "FlutterSharedPreferences"
    private val KEY_BLOCK_ACTIVATED_AT = "flutter.block_activated_at"

    private val vpnSettingsClasses = setOf(
        "VpnSettings",
        "VpnSettingsActivity",
        "com.android.settings.vpn2.VpnSettings",
        "com.android.settings.VpnSettings",
    )

    private val blockedApps = setOf(
        "com.bet9ja.sport",
        "com.sportybet.android",
        "com.betway.android",
        "com.parimatch.android",
        "ng.com.mtn.mytvsports",
        "com.accessbet.android",
        "com.merrybet.android",
        "com.nairabet.android",
        "com.kaizen.gaming.betano",
        "org.torproject.torbrowser",
        "com.opera.mini.native",
        "com.opera.browser",
        "com.brave.browser",
        "com.UCMobile.intl",
        "com.nordvpn.android",
        "com.expressvpn.vpn",
        "com.surfshark.vpnclient.android",
        "com.privateinternetaccess.android",
        "com.windscribe.vpn",
        "com.tunnelbear.android",
        "com.cyberghostvpn.android",
        "com.protonvpn.android",
        "ch.protonvpn.android",
        "com.vpn.free.hotspot.secure.vpnify",
        "free.vpn.unblock.proxy.turbovpn",
        "com.fast.free.unblock.thunder.vpn",
    )

    private val settingsPackages = setOf(
        "com.android.settings",
        "com.samsung.android.settings",
        "com.miui.securitycenter",
        "com.huawei.systemmanager",
        "com.coloros.safecenter",
        "com.vivo.permissionmanagement",
        "com.oneplus.security",
        "com.transsion.phonemaster",
        "com.itel.security",
        "com.infinix.security",
        "com.transsion.security",
        "com.tecno.security",
    )

    private val installerPackages = setOf(
        "com.google.android.packageinstaller",
        "com.android.packageinstaller",
        "com.miui.packageinstaller",
        "com.samsung.android.packageinstaller",
        "com.transsion.packageinstaller",
        "com.infinix.packageinstaller",
        "com.huawei.android.packageinstaller",
        "com.coloros.packageinstaller",
        "com.vivo.packageinstaller",
        "com.oneplus.packageinstaller",
        "com.itel.packageinstaller",
        "com.tecno.packageinstaller",
    )

    private val deviceAdminActivities = setOf(
        "DeviceAdminSettings",
        "DeviceAdminAdd",
        "DeviceAdminInfo",
        "ActiveDeviceAdminInfo",
        "DeviceAdminActivity",
        "DeviceAdminListActivity",
        "device_admin_settings",
    )

    private val appInfoActivities = setOf(
        "AppInfoDashboardFragment",
        "AppStorageSettings",
        "InstalledAppDetails",
        "AppInfoBase",
        "AppDetailActivity",
        "AppInfoActivity",
    )

    // ── Accessibility settings screens ────────────────────────────────────────
    // Covers stock Android + major OEM variants (Samsung, Xiaomi, Huawei etc.)
    // A user navigating here while blocking is active could toggle off the
    // BetControl accessibility service, disabling app blocking entirely.
    private val accessibilitySettingsActivities = setOf(
        "AccessibilitySettings",
        "AccessibilitySettingsActivity",
        "AccessibilityServiceSettingsActivity",
        "SubSettings",                                    // Samsung uses this for sub-pages
        "ToggleAccessibilityServicePreferenceFragment",
        "AccessibilityDetailsSettingsActivity",
        "com.android.settings.accessibility.AccessibilitySettings",
        "com.android.settings.accessibility.AccessibilityServiceSettingsActivity",
        "com.samsung.accessibility.AccessibilitySettings",
        "com.miui.accessibility.AccessibilitySettings",
    )

    // ── Battery / background restriction screens ──────────────────────────────
    // If a user reaches the BetControl battery settings page they could set it
    // to "Restricted" which stops background processes including the VPN service.
    // Block ALL battery detail screens when blocking is active since they are
    // only relevant in the context of the app info page which is also blocked.
    private val batterySettingsActivities = setOf(
        "BatteryUsageActivity",
        "BackgroundOptimizeActivity",
        "HighPowerActivity",
        "AppBatteryUsageActivity",
        "PowerUsageDetail",
        "BatterySaverSettings",
        "AppBatterySettings",
        "AppBatteryUsageDetailsActivity",
        "RestrictedBackgroundActivity",
        "BackgroundDataActivity",
        "com.android.settings.fuelgauge.BackgroundOptimizeActivity",
        "com.android.settings.fuelgauge.batteryusage.PowerUsageDetail",
        "com.samsung.android.settings.battery.BatteryActivity",
        "com.miui.powerkeeper.ui.HideAppsContainerManageActivity",
        "com.huawei.systemmanager.power.ui.AppPowerManagerActivity",
    )

    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceStartTime = System.currentTimeMillis()
        serviceInfo = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                    AccessibilityEvent.TYPE_WINDOWS_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            notificationTimeout = 100
        }
    }

    private fun isBlocking(): Boolean {
        return ProtectionStateStore.read(applicationContext).isActive
    }

    private fun isInAggressiveWindow(): Boolean =
        System.currentTimeMillis() - serviceStartTime < aggressiveWindowMs

    private fun isInVpnSettingsGraceWindow(): Boolean {
        return try {
            val prefs = applicationContext.getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            val activatedAt = prefs.getLong(KEY_BLOCK_ACTIVATED_AT, 0L)
            if (activatedAt == 0L) return false
            System.currentTimeMillis() - activatedAt < vpnSettingsGraceMs
        } catch (e: Exception) {
            false
        }
    }

    private fun isVpnSettingsScreen(event: AccessibilityEvent): Boolean {
        val className = event.className?.toString() ?: return false
        return vpnSettingsClasses.any { className.endsWith(it) || className == it }
    }

    private fun isDeviceAdminScreen(className: String): Boolean {
        return deviceAdminActivities.any { className.endsWith(it) || className == it }
    }

    private fun isAccessibilitySettingsScreen(className: String): Boolean {
        return accessibilitySettingsActivities.any {
            className.endsWith(it) || className == it || className.contains(it)
        }
    }

    private fun isBatterySettingsScreen(className: String): Boolean {
        return batterySettingsActivities.any {
            className.endsWith(it) || className == it || className.contains(it)
        }
    }

    // ── App info screen showing BetControl specifically ───────────────────────
    private fun isBetControlAppInfoScreen(event: AccessibilityEvent): Boolean {
        val className = event.className?.toString() ?: return false
        val isAppInfoScreen = appInfoActivities.any {
            className.endsWith(it) || className == it
        }
        if (!isAppInfoScreen) return false
        val text = event.text?.joinToString(" ")?.lowercase() ?: ""
        val contentDesc = event.contentDescription?.toString()?.lowercase() ?: ""
        return text.contains("betcontrol") || contentDesc.contains("betcontrol")
    }

    private fun sendHome() {
        val now = System.currentTimeMillis()
        if (now - lastSentHome < 600) return
        lastSentHome = now
        performGlobalAction(GLOBAL_ACTION_HOME)
        handler.postDelayed({ performGlobalAction(GLOBAL_ACTION_HOME) }, 150)
        handler.postDelayed({
            try {
                startActivity(Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                })
            } catch (_: Exception) {}
        }, 300)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return

       // ── ALWAYS BLOCK regardless of blocking state ─────────────────────────
// These protect the app from uninstall/deactivation at all times.

if (settingsPackages.contains(pkg)) {
    val className = event.className?.toString() ?: return

    // BetControl app info — always block (prevents force stop + uninstall)
    if (isBetControlAppInfoScreen(event)) {
        sendHome()
        return
    }
}

// Block package installer ONLY when it's trying to uninstall BetControl.
// Checking event text and content description for our package name ensures
// other apps can be uninstalled freely — only BetControl is protected.
if (installerPackages.contains(pkg)) {
    val text = event.text?.joinToString(" ")?.lowercase() ?: ""
    val contentDesc = event.contentDescription?.toString()?.lowercase() ?: ""
    val isBetControlUninstall = text.contains("betcontrol") ||
            contentDesc.contains("betcontrol") ||
            text.contains(packageName.lowercase()) ||
            contentDesc.contains(packageName.lowercase())
    if (isBetControlUninstall) {
        sendHome()
    }
    return
}

        // ── BELOW THIS LINE: only applies when blocking IS active ─────────────
        if (!isBlocking()) return

        // Block gambling/vpn apps
        if (blockedApps.contains(pkg)) {
            sendHome()
            return
        }

        if (settingsPackages.contains(pkg)) {
            val className = event.className?.toString() ?: return

            // Aggressive window — block ALL settings for 10s after service connects
            if (isInAggressiveWindow()) {
                sendHome()
                return
            }

            // VPN settings — only allowed in first 60s after activation
            if (isVpnSettingsScreen(event)) {
                if (isInVpnSettingsGraceWindow()) return
                sendHome()
                return
            }

            // Device admin screens — block when blocking is active
            if (isDeviceAdminScreen(className)) {
                sendHome()
                return
            }

            // ── Accessibility settings — block when blocking is active ─────────
            // User can freely visit this page when not blocking.
            // When blocking is active, reaching here lets them disable the
            // accessibility service which would stop app blocking entirely.
            if (isAccessibilitySettingsScreen(className)) {
                sendHome()
                return
            }

            // ── Battery/background settings — block when blocking is active ────
            // User can freely visit battery settings when not blocking.
            // When blocking is active, reaching here lets them restrict
            // BetControl's background process, killing the VPN service.
            if (isBatterySettingsScreen(className)) {
                sendHome()
                return
            }

            // Everything else in settings — allow freely when blocking is active
            return
        }
    }

    override fun onInterrupt() {}
}