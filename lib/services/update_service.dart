import 'package:in_app_update/in_app_update.dart';
import 'package:flutter/material.dart';

class UpdateService {
  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      final updateInfo = await InAppUpdate.checkForUpdate();

      if (updateInfo.updateAvailability ==
          UpdateAvailability.updateAvailable) {
        await InAppUpdate.startFlexibleUpdate();
        InAppUpdate.completeFlexibleUpdate();
      }
    } catch (_) {
      // Silently fail — never crash the app over an update check
    }
  }
}