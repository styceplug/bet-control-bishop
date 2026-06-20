package com.betcontrol.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.SharedPreferences
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

class BetControlVpnService : VpnService() {

    private var vpnInterface: ParcelFileDescriptor? = null
    private var isRunning = false
    private val handler = Handler(Looper.getMainLooper())

    private val vpnDnsIp = "10.0.0.1"
    private val realDns = "8.8.8.8"
    private val maxRestartAttempts = 30
    private val restartDelayMillis = 1000L

    // Track last expiry check to avoid checking every packet
    private var lastExpiryCheckMs = 0L
    private val expiryCheckIntervalMs = 60_000L // check every 60 seconds

    private val blockedDomains = setOf(
        "1xbet.com", "sportybet.com", "bet9ja.com",
        "betway.com", "parimatch.com", "accessbet.com",
        "merrybet.com", "nairabet.com", "betking.com",
        "msport.com", "bangbet.com", "betlion.com",
        "22bet.com", "melbet.com", "betwinner.com",
        "cloudbet.com", "betmaster.com", "linebet.com",
        "betano.com", "www.betano.com", "betano.ng", "www.betano.ng"
    )

    private fun prefs(): SharedPreferences =
        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)

    private fun isBlocking(): Boolean {
        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        if (flutterPrefs.getBoolean("flutter.is_blocking", false)) return true
        return ProtectionStateStore.read(applicationContext).isActive
    }

    // ── Check if the block timer has expired ──────────────────────────────────
    // Called periodically from runVpnLoop so blocking stops on time
    // even when the app is closed. Reads unlock_time from ProtectionStateStore
    // (native Long, no overflow) rather than Flutter prefs.
    private fun isBlockExpired(): Boolean {
        val unlockTime = ProtectionStateStore.read(applicationContext).unlockTime
        if (unlockTime <= 0L) return false
        return System.currentTimeMillis() >= unlockTime
    }

    // ── Clear block state and stop — mirrors clearExpiredBlock in BootReceiver ─
    private fun clearExpiredBlockAndStop() {
        prefs().edit()
            .putBoolean("flutter.is_blocking", false)
            .putBoolean("flutter.vpn_running", false)
            .putBoolean("flutter.vpn_interrupted", false)
            .remove("flutter.unlock_time")
            .remove("flutter.block_pin")
            .remove("flutter.recovery_alarm_attempt")
            .putBoolean("is_blocking", false)
            .remove("unlock_time")
            .remove("block_pin")
            .apply()
        ProtectionStateStore.clear(applicationContext)
        // Cancel the expiry alarm since we're handling it here
        try {
            BootReceiver().cancelExpiryAlarm(applicationContext)
        } catch (e: Exception) {
            e.printStackTrace()
        }
        stopVpn()
    }

    private fun markVpnRunning(running: Boolean) {
        prefs().edit().putBoolean("flutter.vpn_running", running).apply()
    }

    private fun persistAlwaysOnStatus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            prefs().edit()
                .putBoolean("flutter.always_on_vpn_confirmed", isAlwaysOn)
                .apply()
        }
    }

    private fun markProtectionInterrupted() {
        prefs().edit()
            .putBoolean("flutter.vpn_running", false)
            .putBoolean("flutter.vpn_interrupted", true)
            .apply()
    }

    private fun clearProtectionInterrupted() {
        prefs().edit()
            .putBoolean("flutter.vpn_interrupted", false)
            .putInt("flutter.vpn_restart_attempts", 0)
            .remove("flutter.recovery_alarm_attempt")
            .apply()
    }

    private fun scheduleStubbornRestart(delayMs: Long = 2000L) {
        val preferences = prefs()
        val attempt = preferences.getInt("flutter.vpn_restart_attempts", 0) + 1

        if (attempt > maxRestartAttempts) {
            markProtectionInterrupted()
            return
        }

        scheduleSystemRecovery(attempt, delayMs)

        preferences.edit()
            .putInt("flutter.vpn_restart_attempts", attempt)
            .apply()

        val delay = (restartDelayMillis * attempt.coerceAtMost(5)).coerceAtLeast(delayMs)
        handler.postDelayed({
            if (!isBlocking()) return@postDelayed
            val restartIntent =
                Intent(applicationContext, BetControlVpnService::class.java).apply {
                    action = "START"
                }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    applicationContext.startForegroundService(restartIntent)
                } else {
                    applicationContext.startService(restartIntent)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }, delay)
    }

    private fun scheduleSystemRecovery(attempt: Int, delayMs: Long) {
        try {
            BootReceiver().scheduleRecoveryRetry(
                applicationContext,
                attempt.coerceAtMost(12),
                delayMs
            )
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun requestVpnPermissionViaActivity() {
        try {
            val intent =
                packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("request_vpn_permission", true)
                }
            intent?.let { startActivity(it) }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {

        if (intent?.action == "CHECK_ALWAYS_ON") {
            startForeground(2, buildNotification())
            persistAlwaysOnStatus()
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        }

        if (intent?.action == "STOP") {
            stopVpn()
            return START_NOT_STICKY
        }

        if (!isBlocking()) {
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(1, buildNotification())
        persistAlwaysOnStatus()
        startVpn()
        return START_STICKY
    }

    private fun startVpn() {
        try {
            if (isRunning) return

            val permissionIntent = prepare(applicationContext)
            if (permissionIntent != null) {
                markProtectionInterrupted()
                requestVpnPermissionViaActivity()
                stopSelf()
                return
            }

            val builder = Builder()
                .setSession("BetControl")
                .addAddress("10.0.0.2", 32)
                .addDnsServer(vpnDnsIp)
                .addRoute(vpnDnsIp, 32)
                .setMtu(1500)
                .setBlocking(true)

            builder.addDisallowedApplication(packageName)

            val iface = builder.establish()

            if (iface == null) {
                markProtectionInterrupted()
                scheduleStubbornRestart(3000L)
                stopSelf()
                return
            }

            vpnInterface = iface
            isRunning = true
            markVpnRunning(true)
            clearProtectionInterrupted()

            Thread { runVpnLoop() }.start()
        } catch (e: Exception) {
            e.printStackTrace()
            markVpnRunning(false)
            if (isBlocking()) {
                markProtectionInterrupted()
                scheduleStubbornRestart()
            }
            stopSelf()
        }
    }

    private fun runVpnLoop() {
        val vpnFd = vpnInterface ?: return
        val inputStream = FileInputStream(vpnFd.fileDescriptor)
        val outputStream = FileOutputStream(vpnFd.fileDescriptor)
        val packet = ByteArray(32767)

        while (isRunning) {
            try {
                // ── Periodic expiry check ─────────────────────────────────────
                // Check every 60 seconds whether the block timer has expired.
                // If it has, clear all state and stop — no app open needed.
                val now = System.currentTimeMillis()
                if (now - lastExpiryCheckMs >= expiryCheckIntervalMs) {
                    lastExpiryCheckMs = now
                    if (isBlockExpired()) {
                        clearExpiredBlockAndStop()
                        return
                    }
                }

                val length = inputStream.read(packet)
                if (length <= 0) continue
                val response = handleDnsPacket(packet.copyOf(length), length)
                if (response != null) {
                    outputStream.write(response)
                    outputStream.flush()
                }
            } catch (e: Exception) {
                if (isRunning) e.printStackTrace()
                break
            }
        }

        if (isBlocking()) {
            markProtectionInterrupted()
            scheduleStubbornRestart()
        }
    }

    private fun handleDnsPacket(packet: ByteArray, length: Int): ByteArray? {
        if (length < 28) return null
        val version = (packet[0].toInt() shr 4) and 0x0F
        if (version != 4) return null
        val ipHeaderLength = (packet[0].toInt() and 0x0F) * 4
        if (length < ipHeaderLength + 8) return null
        val protocol = packet[9].toInt() and 0xFF
        if (protocol != 17) return null
        val udpOffset = ipHeaderLength
        val sourcePort = readShort(packet, udpOffset)
        val destinationPort = readShort(packet, udpOffset + 2)
        if (destinationPort != 53) return null
        val udpLength = readShort(packet, udpOffset + 4)
        val dnsOffset = udpOffset + 8
        val dnsLength = udpLength - 8
        if (dnsLength <= 0 || dnsOffset + dnsLength > length) return null
        val dnsQuery = packet.copyOfRange(dnsOffset, dnsOffset + dnsLength)
        val domain = extractDomainFromDnsQuery(dnsQuery)
        val dnsResponse = if (domain != null && isDomainBlocked(domain)) {
            buildNxDomainResponse(dnsQuery)
        } else {
            forwardDnsQuery(dnsQuery) ?: buildServerFailureResponse(dnsQuery)
        }
        val sourceIp = packet.copyOfRange(12, 16)
        val destinationIp = packet.copyOfRange(16, 20)
        return buildUdpIpv4Packet(
            sourceIp = destinationIp,
            destinationIp = sourceIp,
            sourcePort = 53,
            destinationPort = sourcePort,
            payload = dnsResponse
        )
    }

    private fun forwardDnsQuery(query: ByteArray): ByteArray? {
        return try {
            val socket = DatagramSocket()
            protect(socket)
            socket.soTimeout = 3000
            val request = DatagramPacket(
                query, query.size, InetAddress.getByName(realDns), 53
            )
            socket.send(request)
            val responseBuffer = ByteArray(4096)
            val response = DatagramPacket(responseBuffer, responseBuffer.size)
            socket.receive(response)
            socket.close()
            responseBuffer.copyOf(response.length)
        } catch (e: Exception) {
            null
        }
    }

    private fun extractDomainFromDnsQuery(data: ByteArray): String? {
        return try {
            if (data.size < 12) return null
            val sb = StringBuilder()
            var index = 12
            while (index < data.size) {
                val labelLength = data[index].toInt() and 0xFF
                if (labelLength == 0) break
                if (index + labelLength >= data.size) break
                if (sb.isNotEmpty()) sb.append(".")
                sb.append(String(data, index + 1, labelLength, Charsets.US_ASCII))
                index += labelLength + 1
            }
            if (sb.isEmpty()) null else sb.toString().lowercase()
        } catch (e: Exception) {
            null
        }
    }

    private fun isDomainBlocked(domain: String): Boolean =
        blockedDomains.any { blocked -> domain == blocked || domain.endsWith(".$blocked") }

    private fun buildNxDomainResponse(query: ByteArray): ByteArray {
        val response = query.copyOf()
        response[2] = (response[2].toInt() or 0x80).toByte()
        response[3] = ((response[3].toInt() and 0xF0) or 0x03).toByte()
        response[6] = 0; response[7] = 0
        response[8] = 0; response[9] = 0
        response[10] = 0; response[11] = 0
        return response
    }

    private fun buildServerFailureResponse(query: ByteArray): ByteArray {
        val response = query.copyOf()
        response[2] = (response[2].toInt() or 0x80).toByte()
        response[3] = ((response[3].toInt() and 0xF0) or 0x02).toByte()
        return response
    }

    private fun buildUdpIpv4Packet(
        sourceIp: ByteArray, destinationIp: ByteArray,
        sourcePort: Int, destinationPort: Int, payload: ByteArray
    ): ByteArray {
        val ipHeaderLength = 20
        val udpHeaderLength = 8
        val totalLength = ipHeaderLength + udpHeaderLength + payload.size
        val packet = ByteArray(totalLength)
        packet[0] = 0x45; packet[1] = 0
        writeShort(packet, 2, totalLength)
        writeShort(packet, 4, 0); writeShort(packet, 6, 0)
        packet[8] = 64; packet[9] = 17
        System.arraycopy(sourceIp, 0, packet, 12, 4)
        System.arraycopy(destinationIp, 0, packet, 16, 4)
        val ipChecksum = checksum(packet, 0, ipHeaderLength)
        writeShort(packet, 10, ipChecksum)
        val udpOffset = ipHeaderLength
        writeShort(packet, udpOffset, sourcePort)
        writeShort(packet, udpOffset + 2, destinationPort)
        writeShort(packet, udpOffset + 4, udpHeaderLength + payload.size)
        writeShort(packet, udpOffset + 6, 0)
        System.arraycopy(payload, 0, packet, udpOffset + udpHeaderLength, payload.size)
        return packet
    }

    private fun readShort(data: ByteArray, offset: Int): Int =
        ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)

    private fun writeShort(data: ByteArray, offset: Int, value: Int) {
        data[offset] = ((value shr 8) and 0xFF).toByte()
        data[offset + 1] = (value and 0xFF).toByte()
    }

    private fun checksum(data: ByteArray, offset: Int, length: Int): Int {
        var sum = 0; var index = offset
        while (index < offset + length) {
            if (index == 10) { index += 2; continue }
            val word = ((data[index].toInt() and 0xFF) shl 8) or
                    (data[index + 1].toInt() and 0xFF)
            sum += word
            while ((sum and 0xFFFF0000.toInt()) != 0)
                sum = (sum and 0xFFFF) + (sum ushr 16)
            index += 2
        }
        return sum.inv() and 0xFFFF
    }

    private fun stopVpn() {
        isRunning = false
        vpnInterface?.close()
        vpnInterface = null
        markVpnRunning(false)
        stopForeground(true)
        stopSelf()
    }

    private fun buildNotification(): Notification {
        val channelId = "betcontrol_vpn"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId, "BetControl Protection",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("BetControl Active")
            .setContentText("Gambling sites and apps are blocked")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
    }

    override fun onDestroy() {
        isRunning = false
        vpnInterface?.close()
        vpnInterface = null
        markVpnRunning(false)
        // Only restart if blocking is still active (not expired)
        if (isBlocking()) scheduleStubbornRestart(2000L)
        super.onDestroy()
    }

    override fun onRevoke() {
        if (isBlocking()) {
            markProtectionInterrupted()
            isRunning = false
            vpnInterface?.close()
            vpnInterface = null
            markVpnRunning(false)
            scheduleStubbornRestart()
            stopForeground(true)
            stopSelf()
            super.onRevoke()
            return
        }
        stopVpn()
        super.onRevoke()
    }
}