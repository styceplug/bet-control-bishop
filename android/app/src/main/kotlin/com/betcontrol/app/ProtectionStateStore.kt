package com.betcontrol.app

import android.content.Context
import android.content.SharedPreferences
import android.os.Build

object ProtectionStateStore {
    private const val PROTECTED_PREFS = "BetControlProtectionState"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"

    private const val KEY_IS_BLOCKING = "is_blocking"
    private const val KEY_UNLOCK_TIME = "unlock_time"

    private const val FLUTTER_KEY_IS_BLOCKING = "flutter.is_blocking"
    private const val FLUTTER_KEY_UNLOCK_TIME = "flutter.unlock_time"

    data class State(
        val isBlocking: Boolean,
        val unlockTime: Long,
    ) {
        val isActive: Boolean
            get() = isBlocking && unlockTime > System.currentTimeMillis()
    }

    fun read(context: Context): State {
        // Always read from device-protected storage first — this is readable
        // at boot before the user unlocks the phone (direct boot aware).
        val protectedState = readProtected(context)
        if (protectedState.isBlocking || protectedState.unlockTime > 0L) {
            return protectedState
        }

        // Fallback to FlutterSharedPreferences — only readable after unlock.
        // This covers the case where write() was never called (first install,
        // or older build before protected storage was introduced).
        val flutterPrefs = flutterPrefs(context)
        return State(
            isBlocking = flutterPrefs.getBoolean(FLUTTER_KEY_IS_BLOCKING, false),
            unlockTime = readUnlockTimeFromFlutter(flutterPrefs),
        )
    }

    fun syncFromFlutterPrefs(context: Context) {
        val flutterPrefs = flutterPrefs(context)
        write(
            context = context,
            isBlocking = flutterPrefs.getBoolean(FLUTTER_KEY_IS_BLOCKING, false),
            unlockTime = readUnlockTimeFromFlutter(flutterPrefs),
        )
    }

    fun write(context: Context, isBlocking: Boolean, unlockTime: Long) {
        // Write to device-protected storage so it survives reboot and is
        // readable by BootReceiver before the user unlocks the phone.
        protectedPrefs(context).edit()
            .putBoolean(KEY_IS_BLOCKING, isBlocking)
            .putLong(KEY_UNLOCK_TIME, unlockTime)
            .apply()
    }

    fun clear(context: Context) {
        protectedPrefs(context).edit()
            .putBoolean(KEY_IS_BLOCKING, false)
            .remove(KEY_UNLOCK_TIME)
            .apply()
    }

    private fun readProtected(context: Context): State {
        val prefs = protectedPrefs(context)
        return State(
            isBlocking = prefs.getBoolean(KEY_IS_BLOCKING, false),
            unlockTime = prefs.getLong(KEY_UNLOCK_TIME, 0L),
        )
    }

    // ── Device-protected storage context ─────────────────────────────────────
    // Critical: if the context is already a device-protected context (e.g. when
    // called from BootReceiver at boot), calling createDeviceProtectedStorageContext()
    // again on it creates a nested protected context that resolves to a DIFFERENT
    // path on some devices — causing read/write mismatches.
    // We check isDeviceProtectedStorage first to avoid double-wrapping.
    private fun protectedPrefs(context: Context): SharedPreferences {
        val storageContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                context.isDeviceProtectedStorage) {
                // Already in device-protected context — use as-is
                context
            } else {
                // Credential-encrypted context — convert to device-protected
                context.createDeviceProtectedStorageContext()
            }
        } else {
            context
        }
        return storageContext.getSharedPreferences(PROTECTED_PREFS, Context.MODE_PRIVATE)
    }

    // ── Flutter unlock_time reading ───────────────────────────────────────────
    // Flutter's SharedPreferences plugin stores int values as Int (32-bit).
    // Native syncBlockState writes via putLong. We try getLong first,
    // and if it returns 0, fall back to getInt (which is what Flutter wrote).
    private fun readUnlockTimeFromFlutter(prefs: SharedPreferences): Long {
        val asLong = prefs.getLong(FLUTTER_KEY_UNLOCK_TIME, 0L)
        if (asLong > 0L) return asLong
        return try {
            prefs.getInt(FLUTTER_KEY_UNLOCK_TIME, 0).toLong()
        } catch (e: ClassCastException) {
            0L
        }
    }

    private fun flutterPrefs(context: Context): SharedPreferences =
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
}