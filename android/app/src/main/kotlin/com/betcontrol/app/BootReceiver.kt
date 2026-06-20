package com.betcontrol.app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationCompat

class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action !in validActions) return

        // ── Read state — flutter.is_blocking is the primary source ────────────
        // unlock_time from FlutterSharedPreferences is NOT used for expiry checks
        // here because Flutter's setInt() overflows for ms timestamps.
        // ProtectionStateStore holds the reliable Long written by native syncBlockState.
        val now = System.currentTimeMillis()
        val flutterPrefs = prefs(context)
        val flutterBlocking = flutterPrefs.getBoolean("flutter.is_blocking", false)
        val protectedState = ProtectionStateStore.read(context)

        val isBlocking = flutterBlocking || protectedState.isBlocking
        val unlockTime = protectedState.unlockTime

        if (!isBlocking) {
            clearRecoveryAttempts(context)
            return
        }

        // Handle expiry alarm — clears block natively without needing app open
        if (action == ACTION_BLOCK_EXPIRED) {
            clearExpiredBlock(context)
            cancelRestorationNotification(context)
            return
        }

        // Check expiry from protected storage (reliable Long)
        if (unlockTime > 0L && unlockTime <= now) {
            clearExpiredBlock(context)
            return
        }

        val recoveryAttempt = intent.getIntExtra(EXTRA_RECOVERY_ATTEMPT, 0)

        withShortWakeLock(context) {
            restoreVpn(context)

            when (action) {
                PowerManager.ACTION_POWER_SAVE_MODE_CHANGED -> {
                    val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                    if (pm.isPowerSaveMode) {
                        scheduleRecoveryRetry(context, 1, 60_000L)
                    } else {
                        scheduleRecoveryBurst(context)
                    }
                }

                Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_LOCKED_BOOT_COMPLETED,
                Intent.ACTION_USER_UNLOCKED,
                "android.intent.action.QUICKBOOT_POWERON",
                "com.htc.intent.action.QUICKBOOT_POWERON",
                Intent.ACTION_MY_PACKAGE_REPLACED -> {
                    scheduleRecoveryBurst(context)
                    restoreProtectionChecks(context)
                    // Re-schedule expiry alarm in case it was lost during reboot
                    if (unlockTime > now) {
                        scheduleExpiryAlarm(context, unlockTime)
                    }
                }

                ACTION_RESTORE_PROTECTION -> {
                    restoreProtectionChecks(context)
                    scheduleNextRecoveryIfNeeded(context, recoveryAttempt)
                }

                Intent.ACTION_SCREEN_ON,
                Intent.ACTION_USER_PRESENT -> {
                    scheduleRecoveryRetry(context, 1, 5_000L)
                    restoreProtectionChecks(context)
                }
            }
        }
    }

    private fun restoreVpn(context: Context) {
        try {
            val vpnIntent = Intent(context, BetControlVpnService::class.java).apply {
                action = "START"
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(vpnIntent)
            } else {
                context.startService(vpnIntent)
            }
        } catch (e: Exception) {
            markProtectionInterrupted(context)
            scheduleRecoveryRetry(context, nextAttempt(context), 15_000L)
        }
    }

    private fun restoreProtectionChecks(context: Context) {
        try {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE)
                    as DevicePolicyManager
            val adminComponent = ComponentName(context, BetControlDeviceAdmin::class.java)
            val needsUserAction =
                !dpm.isAdminActive(adminComponent) || !isAccessibilityEnabled(context)

            if (needsUserAction) {
                showRestorationNotification(context)
                launchRestorationOverlay(context)
            } else {
                cancelRestorationNotification(context)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun launchRestorationOverlay(context: Context) {
        try {
            val overlayIntent = Intent(context, RestorationOverlayActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_NO_HISTORY
            }
            context.startActivity(overlayIntent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun scheduleRecoveryBurst(context: Context) {
        scheduleRecoveryRetry(context, 1, 5_000L)
        scheduleRecoveryRetry(context, 2, 15_000L)
        scheduleRecoveryRetry(context, 3, 30_000L)
        scheduleRecoveryRetry(context, 4, 60_000L)
        scheduleRecoveryRetry(context, 5, 120_000L)
        scheduleRecoveryRetry(context, 6, 300_000L)
    }

    private fun scheduleNextRecoveryIfNeeded(context: Context, currentAttempt: Int) {
        if (!isStillBlocking(context)) return

        val nextAttempt = (currentAttempt + 1).coerceAtLeast(1)
        if (nextAttempt > MAX_RECOVERY_ATTEMPTS) {
            markProtectionInterrupted(context)
            return
        }

        val delay = when {
            nextAttempt <= 3 -> 30_000L
            nextAttempt <= 6 -> 60_000L
            nextAttempt <= 9 -> 5 * 60_000L
            else -> 15 * 60_000L
        }
        scheduleRecoveryRetry(context, nextAttempt, delay)
    }

    fun scheduleExpiryAlarm(context: Context, unlockTimeMs: Long) {
        if (unlockTimeMs <= 0L) return
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            EXPIRY_REQUEST_CODE,
            Intent(context, BootReceiver::class.java).apply {
                action = ACTION_BLOCK_EXPIRED
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP, unlockTimeMs, pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP, unlockTimeMs, pendingIntent
            )
        }
    }

    fun cancelExpiryAlarm(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            EXPIRY_REQUEST_CODE,
            Intent(context, BootReceiver::class.java).apply {
                action = ACTION_BLOCK_EXPIRED
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
    }

    fun scheduleRecoveryRetry(context: Context, attempt: Int, delayMs: Long) {
        if (attempt > MAX_RECOVERY_ATTEMPTS) {
            markProtectionInterrupted(context)
            return
        }

        prefs(context).edit()
            .putInt(KEY_RECOVERY_ATTEMPT, attempt)
            .apply()

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            RECOVERY_REQUEST_CODE + attempt,
            Intent(context, BootReceiver::class.java).apply {
                action = ACTION_RESTORE_PROTECTION
                putExtra(EXTRA_RECOVERY_ATTEMPT, attempt)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val triggerAt = System.currentTimeMillis() + delayMs

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent
            )
        } else {
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        }
    }

    private fun nextAttempt(context: Context): Int =
        prefs(context).getInt(KEY_RECOVERY_ATTEMPT, 0) + 1

    private fun clearRecoveryAttempts(context: Context) {
        prefs(context).edit()
            .remove(KEY_RECOVERY_ATTEMPT)
            .apply()
    }

    private fun markProtectionInterrupted(context: Context) {
        prefs(context).edit()
            .putBoolean(KEY_VPN_RUNNING, false)
            .putBoolean(KEY_VPN_INTERRUPTED, true)
            .apply()
    }

    // ── Clear block on expiry — writes BOTH key forms so Flutter reads it ─────
    //
    // block_services.dart reads via Flutter's SharedPreferences plugin which
    // uses the bare key 'is_blocking' (stored as 'flutter.is_blocking' on disk).
    // Native code reads 'flutter.is_blocking' directly.
    //
    // We write both to ensure the cancellation is seen regardless of which
    // path reads it first.
    private fun clearExpiredBlock(context: Context) {
        prefs(context).edit()
            // Flutter plugin key (what native code reads directly)
            .putBoolean("flutter.is_blocking", false)
            .putBoolean("flutter.vpn_running", false)
            .putBoolean("flutter.vpn_interrupted", false)
            .remove("flutter.unlock_time")
            .remove("flutter.block_pin")
            .remove(KEY_RECOVERY_ATTEMPT)
            // Bare key (what Flutter's SharedPreferences.getBool('is_blocking') reads)
            // Flutter prepends 'flutter.' when writing, but reads the bare key.
            // Writing the bare key here ensures init() in block_services.dart
            // sees isBlocking = false immediately on next app open.
            .putBoolean("is_blocking", false)
            .remove("unlock_time")
            .remove("block_pin")
            .apply()

        ProtectionStateStore.clear(context)

        try {
            context.startService(
                Intent(context, BetControlVpnService::class.java).apply {
                    action = "STOP"
                }
            )
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun isAccessibilityEnabled(context: Context): Boolean {
        return try {
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            enabled.contains(context.packageName)
        } catch (e: Exception) {
            false
        }
    }

    private fun showRestorationNotification(context: Context) {
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "betcontrol_restore_protection"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "BetControl Protection Recovery",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts when BetControl needs user action to restore protection."
                setShowBadge(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val overlayIntent = Intent(context, RestorationOverlayActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            RESTORATION_NOTIFICATION_ID,
            overlayIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("⚠️ BetControl: Protection paused")
            .setContentText("Tap to restore blocking — gambling apps may be accessible.")
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "BetControl's blocking paused after your phone restarted. " +
                    "Tap here to restore protection immediately."
                )
            )
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .build()

        notificationManager.notify(RESTORATION_NOTIFICATION_ID, notification)
    }

    private fun cancelRestorationNotification(context: Context) {
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(RESTORATION_NOTIFICATION_ID)
    }

    private fun withShortWakeLock(context: Context, block: () -> Unit) {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "${context.packageName}:ProtectionRecovery"
        )
        try {
            wakeLock.acquire(10_000L)
            block()
        } finally {
            if (wakeLock.isHeld) wakeLock.release()
        }
    }

    private fun isStillBlocking(context: Context): Boolean {
        val flutterBlocking = prefs(context).getBoolean("flutter.is_blocking", false)
        if (flutterBlocking) return true
        return ProtectionStateStore.read(context).isActive
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    companion object {
        const val ACTION_RESTORE_PROTECTION =
            "com.betcontrol.app.action.RESTORE_PROTECTION"
        const val ACTION_BLOCK_EXPIRED =
            "com.betcontrol.app.action.BLOCK_EXPIRED"

        private const val EXTRA_RECOVERY_ATTEMPT = "recovery_attempt"
        private const val RECOVERY_REQUEST_CODE = 7000
        private const val EXPIRY_REQUEST_CODE = 8000
        private const val MAX_RECOVERY_ATTEMPTS = 12
        private const val RESTORATION_NOTIFICATION_ID = 9001

        private const val KEY_IS_BLOCKING = "flutter.is_blocking"
        private const val KEY_UNLOCK_TIME = "flutter.unlock_time"
        private const val KEY_BLOCK_PIN = "flutter.block_pin"
        private const val KEY_VPN_RUNNING = "flutter.vpn_running"
        private const val KEY_VPN_INTERRUPTED = "flutter.vpn_interrupted"
        private const val KEY_RECOVERY_ATTEMPT = "flutter.recovery_alarm_attempt"

        private val validActions = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_USER_UNLOCKED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED,
            PowerManager.ACTION_POWER_SAVE_MODE_CHANGED,
            Intent.ACTION_SCREEN_ON,
            Intent.ACTION_USER_PRESENT,
            ACTION_RESTORE_PROTECTION,
            ACTION_BLOCK_EXPIRED,
        )
    }
}