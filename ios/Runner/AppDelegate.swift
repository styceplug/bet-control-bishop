import Flutter
import NetworkExtension
import UIKit



@available(iOS 14.0, *)
@main
@objc class AppDelegate: FlutterAppDelegate {
  private let appGroupId = "group.com.project.betcontrolMain"
  private let dnsExtensionBundleId = "com.project.betcontrolMain.DNSFilterExtension"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let registrar = self.registrar(forPlugin: "BlockerPlugin")!
    let blockerChannel = FlutterMethodChannel(
      name: "com.betcontrol/blocker",
      binaryMessenger: registrar.messenger()
    )

    blockerChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleBlockerCall(call, result: result)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleBlockerCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startVpn", "requestVpnPermission":
      enableDNSProxy { success, error in
        if success {
          result(call.method == "startVpn" ? "started" : "already_granted")
        } else {
          result(
            FlutterError(
              code: "dns_proxy_enable_failed",
              message: error?.localizedDescription ?? "DNS proxy could not be enabled.",
              details: nil
            )
          )
        }
      }

    case "stopVpn":
      setDNSProxyEnabled(false) { success, error in
        if success {
          result("stopped")
        } else {
          result(
            FlutterError(
              code: "dns_proxy_disable_failed",
              message: error?.localizedDescription ?? "DNS proxy could not be disabled.",
              details: nil
            )
          )
        }
      }

    case "isVpnPermissionGranted":
      loadDNSProxyManager { manager, error in
        if let error = error {
          NSLog("BetControl DNS proxy status error: \(error.localizedDescription)")
          result(false)
          return
        }
        // "Granted" means we've previously configured a provider bundle ID,
        // not just that the manager object exists (it always exists).
        result(manager?.providerProtocol?.providerBundleIdentifier != nil)
      }

    // NEW: Handles the App Group status check for Flutter
    case "getNativeVpnInterrupted":
      let defaults = UserDefaults(suiteName: appGroupId)
      let interrupted = defaults?.bool(forKey: "vpn_interrupted") ?? false
      result(interrupted)

    case "syncBlockState":
      syncBlockState(arguments: call.arguments)
      result(nil)

    case "getNativeUnlockTime":
      let defaults = UserDefaults(suiteName: appGroupId)
      let unlockTime = defaults?.double(forKey: "unlockTime") ?? 0
      result(unlockTime > 0 ? Int64(unlockTime) : nil)

    case "clearRestorationNotification":
      result(nil)

    case "hasConflictingVpn",
         "isAlwaysOnVpnEnabled",
         "isAccessibilityEnabled",
         "isDeviceAdminActive",
         "isBatteryOptimizationExempt",
         "isPowerSaveModeOn":
      result(false)

    case "requestDeviceAdmin",
         "openAccessibilitySettings",
         "openAlwaysOnVpnSettings",
         "openAutoStartSettings",
         "requestBatteryOptimizationExemption":
      result(nil)

    case "openVpnSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
      result("opened")

    case "getManufacturer":
      result("ios")

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func enableDNSProxy(completion: @escaping (Bool, Error?) -> Void) {
    setDNSProxyEnabled(true, completion: completion)
  }

  /// Activates (or deactivates) the custom NEDNSProxyProvider extension
  /// (DNSFilterExtension / DNSProxyProvider.swift), which is what actually
  /// runs the gambling-domain blocklist + NXDOMAIN logic. This REPLACES the
  /// old NEDNSSettingsManager-based approach, which only swapped the system
  /// DNS resolver and never touched our custom blocking code at all.
  private func setDNSProxyEnabled(_ enabled: Bool, completion: @escaping (Bool, Error?) -> Void) {
    let manager = NEDNSProxyManager.shared()

    manager.loadFromPreferences { [weak self] error in
      guard let self = self else { return }

      if let error = error {
        completion(false, error)
        return
      }

      if !enabled {
        manager.isEnabled = false
        manager.saveToPreferences { saveError in
          completion(saveError == nil, saveError)
        }
        return
      }

      manager.localizedDescription = "BetControl DNS Filter"
      let proto = NEDNSProxyProviderProtocol()
      proto.providerBundleIdentifier = self.dnsExtensionBundleId
      manager.providerProtocol = proto
      manager.isEnabled = true

      manager.saveToPreferences { saveError in
        if let saveError = saveError {
          let errStr = saveError.localizedDescription.lowercased()
          if errStr.contains("unchanged") {
            completion(true, nil) // Treat "unchanged" as success
          } else {
            completion(false, saveError)
          }
        } else {
          // Clean up the old, now-unused DNS Settings (DoH) profile so it
          // doesn't linger as a confusing second entry in Settings > DNS.
          NEDNSSettingsManager.shared().loadFromPreferences { _ in
            NEDNSSettingsManager.shared().removeFromPreferences { _ in
              completion(true, nil)
            }
          }
        }
      }
    }
  }

  private func loadDNSProxyManager(completion: @escaping (NEDNSProxyManager?, Error?) -> Void) {
    let manager = NEDNSProxyManager.shared()
    manager.loadFromPreferences { error in
      completion(manager, error)
    }
  }

  // Update syncBlockState to catch the new parameter
  private func syncBlockState(arguments: Any?) {
    guard let args = arguments as? [String: Any] else { return }
    let isBlocking = args["isBlocking"] as? Bool ?? false
    let hasActiveSubscription = args["hasActiveSubscription"] as? Bool ?? false // Get the flag from Dart

    let unlockTime: Double
    if let value = args["unlockTime"] as? Double {
      unlockTime = value
    } else if let value = args["unlockTime"] as? Int64 {
      unlockTime = Double(value)
    } else if let value = args["unlockTime"] as? Int {
      unlockTime = Double(value)
    } else {
      unlockTime = 0
    }

    let defaults = UserDefaults(suiteName: appGroupId)
    defaults?.set(isBlocking, forKey: "isBlocking")
    defaults?.set(hasActiveSubscription, forKey: "hasActiveSubscription") // Save it for the native side to read
    defaults?.set(unlockTime, forKey: "unlockTime")
    if !isBlocking {
        defaults?.set(false, forKey: "vpn_interrupted")
    }
    defaults?.synchronize()
  }
}