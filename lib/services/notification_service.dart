import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Background message handler — must be top-level function ──────────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(
      const InitializationSettings(android: androidSettings));

  final notification = message.notification;
  final android = message.notification?.android;
  if (notification != null && android != null) {
    await plugin.show(
      message.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'betcontrol_alerts',
          'BetControl Alerts',
          channelDescription:
              'Trial and subscription notifications from BetControl',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFF00D4AA),
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  static const int _trialWarning24hId  = 1001; // 24h before trial ends
  static const int _trialWarning1hId   = 1002; // 1h before trial ends
  static const int _trialExpiredId     = 1003; // at trial end
  static const int _subWarning5dId     = 1004; // 5 days before sub expires
  static const int _subWarning1dId     = 1005; // 1 day before sub expires

  // ── Platform channel to read the device's IANA timezone name ─────────────
  // This is the most reliable way to get the correct local timezone on Android.
  // Requires no extra package — reads directly from the OS.
  static const _tzChannel = MethodChannel('com.betcontrol/timezone');

  static const _androidChannel = AndroidNotificationChannel(
    'betcontrol_alerts',
    'BetControl Alerts',
    description: 'Trial and subscription notifications from BetControl',
    importance: Importance.high,
    ledColor: Color(0xFF00D4AA),
  );

  bool _timezoneReady = false;

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    tz.initializeTimeZones();
    await _syncDeviceTimezone();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
          android: androidSettings, iOS: iosSettings),
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_androidChannel);

    // Request exact alarm permission on Android 12+ — required for
    // scheduled notifications to fire at the correct time.
    await _requestExactAlarmPermission();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final android = message.notification?.android;
      if (notification != null && android != null) {
        _plugin.show(
          message.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'betcontrol_alerts',
              'BetControl Alerts',
              channelDescription:
                  'Trial and subscription notifications from BetControl',
              importance: Importance.high,
              priority: Priority.high,
              color: Color(0xFF00D4AA),
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }
    });

    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  // ── Sync device timezone ──────────────────────────────────────────────────
  // Reads the IANA timezone name from native Android (e.g. "Africa/Lagos").
  // Falls back to UTC offset if the channel isn't wired yet.
  Future<void> _syncDeviceTimezone() async {
    try {
      final tzName =
          await _tzChannel.invokeMethod<String>('getTimezoneName');
      if (tzName != null && tzName.isNotEmpty) {
        try {
          tz.setLocalLocation(tz.getLocation(tzName));
          _timezoneReady = true;
          return;
        } catch (_) {
          // Unknown timezone name — fall through to offset approach
        }
      }
    } catch (_) {
      // Channel not yet implemented — fall through
    }

    // Fallback: find a timezone matching the device's UTC offset.
    // Not perfect but far better than defaulting to UTC.
    final offsetHours = DateTime.now().timeZoneOffset.inHours;
    final offsetMinutes = DateTime.now().timeZoneOffset.inMinutes % 60;
    final offsetSign = offsetHours >= 0 ? '+' : '-';
    final hh = offsetHours.abs().toString().padLeft(2, '0');
    final mm = offsetMinutes.abs().toString().padLeft(2, '0');
    final tzId = 'Etc/GMT${offsetSign == '+' ? '-' : '+'}${offsetHours.abs()}';

    try {
      tz.setLocalLocation(tz.getLocation(tzId));
      _timezoneReady = true;
    } catch (_) {
      // Etc/GMT+X failed — truly fall back to UTC, better than crashing
      tz.setLocalLocation(tz.UTC);
      _timezoneReady = true;
    }

    debugPrint(
        'BetControl timezone: UTC$offsetSign$hh:$mm → using $tzId');
  }

  // ── Request exact alarm permission (Android 12+ / API 31+) ───────────────
  // Without this, zonedSchedule with exactAllowWhileIdle is silently ignored.
  Future<void> _requestExactAlarmPermission() async {
    try {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      // requestExactAlarmsPermission() is available in
      // flutter_local_notifications >= 14.x
      await androidPlugin?.requestExactAlarmsPermission();
    } catch (_) {
      // Older plugin version — ignore, notifications will still fire
      // but may be slightly delayed on Android 12+
    }
  }

  // ── Request notification permissions ─────────────────────────────────────
  Future<void> requestPermission() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  // ── Get FCM token ─────────────────────────────────────────────────────────
  Future<String?> getFcmToken() async {
    try {
      return await _fcm.getToken();
    } catch (_) {
      return null;
    }
  }

  // ── Schedule trial notifications ──────────────────────────────────────────
  // Schedules TWO warnings (24h + 1h before expiry) and one at expiry.
  // Called from block_screen._listenToSubscription() when trial status fires.
  Future<void> scheduleTrialWarning(DateTime trialEndTime) async {
    if (!_timezoneReady) await _syncDeviceTimezone();
    await _cancelTrialNotifications();

    final now = DateTime.now();

    // ── 24-hour warning ───────────────────────────────────────────────────
    final warning24h = trialEndTime.subtract(const Duration(hours: 24));
    if (warning24h.isAfter(now)) {
      await _scheduleNotification(
        id: _trialWarning24hId,
        title: '⏳ Free trial ending tomorrow',
        body:
            'Your BetControl trial ends in 24 hours. Subscribe now to keep your protection active.',
        scheduledTime: warning24h,
      );
    }

    // ── 1-hour warning ────────────────────────────────────────────────────
    final warning1h = trialEndTime.subtract(const Duration(hours: 1));
    if (warning1h.isAfter(now)) {
      await _scheduleNotification(
        id: _trialWarning1hId,
        title: '🚨 Trial ends in 1 hour',
        body:
            'Your free trial expires very soon. Subscribe to prevent gambling sites from being unblocked.',
        scheduledTime: warning1h,
      );
    }
  }

  // ── Schedule trial-expired notification ───────────────────────────────────
  Future<void> scheduleTrialExpired(DateTime trialEndTime) async {
    if (!_timezoneReady) await _syncDeviceTimezone();
    if (trialEndTime.isBefore(DateTime.now())) return;

    await _plugin.cancel(_trialExpiredId);
    await _scheduleNotification(
      id: _trialExpiredId,
      title: '🔓 Trial expired — protection off',
      body:
          'Your free trial has ended. Subscribe now to keep gambling sites blocked.',
      scheduledTime: trialEndTime,
    );
  }

  // ── Schedule subscription expiry warnings ─────────────────────────────────
  // Call this when a paid subscription is confirmed active.
  // Fires at 5 days and 1 day before the subscription expires.
  Future<void> scheduleSubscriptionWarnings(DateTime expiryTime) async {
    if (!_timezoneReady) await _syncDeviceTimezone();
    await _cancelSubscriptionNotifications();

    final now = DateTime.now();

    // ── 5-day warning ─────────────────────────────────────────────────────
    final warning5d = expiryTime.subtract(const Duration(days: 5));
    if (warning5d.isAfter(now)) {
      await _scheduleNotification(
        id: _subWarning5dId,
        title: '📅 Subscription renewing in 5 days',
        body:
            'Your BetControl subscription expires on ${_formatDate(expiryTime)}. Renew to stay protected.',
        scheduledTime: warning5d,
      );
    }

    // ── 1-day warning ─────────────────────────────────────────────────────
    final warning1d = expiryTime.subtract(const Duration(days: 1));
    if (warning1d.isAfter(now)) {
      await _scheduleNotification(
        id: _subWarning1dId,
        title: '⚠️ Subscription expires tomorrow',
        body:
            'Your protection ends tomorrow. Renew now to keep gambling sites blocked.',
        scheduledTime: warning1d,
      );
    }
  }

  // ── Cancel trial notifications ────────────────────────────────────────────
  Future<void> cancelTrialNotifications() async =>
      _cancelTrialNotifications();

  Future<void> _cancelTrialNotifications() async {
    await _plugin.cancel(_trialWarning24hId);
    await _plugin.cancel(_trialWarning1hId);
    await _plugin.cancel(_trialExpiredId);
  }

  // ── Cancel subscription notifications ────────────────────────────────────
  Future<void> cancelSubscriptionNotifications() async =>
      _cancelSubscriptionNotifications();

  Future<void> _cancelSubscriptionNotifications() async {
    await _plugin.cancel(_subWarning5dId);
    await _plugin.cancel(_subWarning1dId);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // ── Core schedule helper ──────────────────────────────────────────────────
  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    try {
      final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);

      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'betcontrol_alerts',
            'BetControl Alerts',
            channelDescription:
                'Trial and subscription notifications from BetControl',
            importance: Importance.high,
            priority: Priority.high,
            color: const Color(0xFF00D4AA),
            icon: '@mipmap/ic_launcher',
            styleInformation: BigTextStyleInformation(body),
            // Show as heads-up notification even when phone is idle
            fullScreenIntent: false,
            enableVibration: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.active,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      debugPrint(
          'BetControl notification $id scheduled for ${scheduledTime.toLocal()}');
    } catch (e) {
      debugPrint('BetControl notification $id scheduling failed: $e');
    }
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}