import Flutter
import FamilyControls
import ManagedSettings
import NetworkExtension
import StoreKit
import SwiftUI
import UIKit

@available(iOS 14.0, *)
@main
@objc class AppDelegate: FlutterAppDelegate {
  private let appGroupId = "group.com.project.betcontrolMain"
  private let packetTunnelExtensionBundleId = "com.project.betcontrolMain.DNSFilterExtension"
  private let packetTunnelDescription = "BetControl Website Shield"
  private let dnsSettingsDescription = "BetControl Website Shield"
  private let dnsSettingsDoHURL = "https://d.adguard-dns.com/dns-query/be6cf9bb"
  private let dnsSettingsBootstrapServers = ["94.140.14.14", "94.140.15.15"]
  private let dnsSettingsMatchDomains = [""]
  private let dnsDebugEnabledKey = "dnsDebugEnabled"
  private let dnsDebugEventsKey = "dnsDebugEvents"
  private let dnsDebugSequenceKey = "dnsDebugSequence"
  private let familyActivitySelectionKey = "familyActivitySelection"
  private let screenTimeStore = ManagedSettingsStore()
  private let blockedAppBundleIdentifiers: Set<String> = [
    "com.1xbet.sport",
    "com.888holdings.casino",
    "com.TTBet.nigeria",
    "com.accessbet.app",
    "com.aliengain.betpawa",
    "com.babaijebu",
    "com.banbet.limited",
    "com.bangbet.app",
    "com.barstoolsportsbook",
    "com.bet365.bet365",
    "com.bet9ja.sport",
    "com.bet9ja.sportsbook.app",
    "com.betfair.sportsbook",
    "com.betika.app",
    "com.betmgm.sports",
    "com.betpawa.app",
    "com.betrivers.sportsbook",
    "com.betvictor.app",
    "com.betway.nigeria.Betway",
    "com.betway.sports",
    "com.betwinner.ios",
    "com.betwinner.ios.nigeria",
    "com.bwin.sports",
    "com.caesars.sportsbook",
    "com.casumo.app",
    "com.coral.sportsbook",
    "com.draftkings.dknativermgdg",
    "com.draftkings.sportsbook",
    "com.espn.bet",
    "com.fanduel.racing",
    "com.fanduel.sportsbook",
    "com.fliff.app",
    "com.hardrockdigital.sportsbook",
    "com.hopegaming.msport",
    "com.ilot.ilotApp",
    "com.kalshi.app",
    "com.kingmakers.bk",
    "com.ladbrokes.sportsbook",
    "com.leovegas.casino",
    "com.linebet.app",
    "com.melbet.client",
    "com.merrybet.app",
    "com.msport.nigeria",
    "com.nairabet.app",
    "com.nairabet.sportsbook",
    "com.ng.OnexBet",
    "com.paddypower.sportsbook",
    "com.parimatch.app",
    "com.paripesa.mediamart",
    "com.partypoker",
    "com.pingco.easywinlotto",
    "com.pointsbet.sportsbook",
    "com.pokerstars.casino",
    "com.pokerstars.poker",
    "com.premierbet.app",
    "com.prizepicks.app",
    "com.skybet.app",
    "com.sleeper.sleeper",
    "com.sportpesa.app",
    "com.sportybet.SportyBet",
    "com.stoiximan.BetanoRo",
    "com.stoiximan.betano",
    "com.thescore.bet",
    "com.tipico.sportsbook",
    "com.underdog.fantasy",
    "com.unibet.sportsbook",
    "com.williamhill.sports",
    "com.williamhill.us.sportsbook",
    "helabet.ng.aleh",
    "ng.melbet.app",
    "org.xbet.client1",
    "org.xbet.client1xbet",
    "uk.co.williamhill.sportsbook"
  ]
  private let blockedWebDomains: Set<String> = [
    "10bet.com",
    "1960bet.com",
    "1win.com",
    "1win.ng",
    "1xbet.co.ke",
    "1xbet.co.tz",
    "1xbet.co.ug",
    "1xbet.com",
    "1xbet.com.gh",
    "1xbet.com.ng",
    "1xbet.net",
    "1xbet.ng",
    "1xstavka.ru",
    "22bet.com",
    "22bet.com.gh",
    "22bet.ng",
    "7bitcasino.com",
    "888.com",
    "888casino.com",
    "888poker.com",
    "888sport.com",
    "888starz.com",
    "9japredict.com",
    "accessbet.com",
    "babaijebu.com",
    "babaijebu.ng",
    "bangbet.co.ke",
    "bangbet.co.tz",
    "bangbet.com",
    "bangbet.ng",
    "barstoolsportsbook.com",
    "bc.game",
    "bet365.bet",
    "bet365.com",
    "bet365.ng",
    "bet9ja.com",
    "bet9ja.net",
    "bet9ja.ng",
    "betano.com",
    "betano.ng",
    "betbonanza.com",
    "betbonanza.ng",
    "betcools.com",
    "betcorrect.com",
    "betcorrect.ng",
    "betfair.com",
    "betfair.com.au",
    "betfair.es",
    "betfair.ie",
    "betfair.it",
    "betfred.com",
    "betika.com",
    "betika.ng",
    "betking.com",
    "betking.com.ng",
    "betking.ng",
    "betland.com",
    "betland.ng",
    "betlion.com",
    "betlion.ng",
    "betmaster.com",
    "betmaster.ng",
    "betmgm.com",
    "betnaija.com",
    "betobet.com",
    "betonline.ag",
    "betpawa.co.gh",
    "betpawa.co.ug",
    "betpawa.co.zm",
    "betpawa.com",
    "betpawa.ng",
    "betr.com",
    "betrivers.com",
    "betsafe.com",
    "betsson.com",
    "betus.com",
    "betvictor.com",
    "betway.co.za",
    "betway.com",
    "betway.com.gh",
    "betway.com.ng",
    "betway.ke",
    "betway.net",
    "betway.ng",
    "betway.tz",
    "betway.zm",
    "betwinner.com",
    "betwinner.ng",
    "bitsler.com",
    "bitstarz.com",
    "bovada.lv",
    "boylesports.com",
    "bwin.com",
    "bwin.de",
    "bwin.es",
    "bwin.it",
    "caesars.com",
    "casebattle.com",
    "casino.com",
    "casumo.com",
    "cloudbet.com",
    "coral.co.uk",
    "coral.com",
    "csgoempire.com",
    "csgoroll.com",
    "dafabet.com",
    "datdrop.com",
    "draftkings.com",
    "duelbits.com",
    "easywin.com",
    "easywin.ng",
    "espnbet.com",
    "fanatics.com",
    "fanduel.com",
    "fliff.com",
    "fortunejack.com",
    "gamdom.com",
    "garlicbets.com",
    "garlicbets.net",
    "gg.bet",
    "ggbet.com",
    "ggpoker.com",
    "goldenbetsport.com",
    "hardrock.bet",
    "helabet.com",
    "helabet.com.ng",
    "holiganbet.com",
    "hollywood-bet.com",
    "hollywoodbets.com",
    "hollywoodbets.mobi",
    "hype.bet",
    "ignition.casino",
    "ilot.com",
    "ilotbet.com",
    "intertops.eu",
    "jackpotcity.com",
    "kalshi.com",
    "kenya.betika.com",
    "ladbrokes.com",
    "ladbrokes.com.au",
    "ladbrokes.ie",
    "leovegas.com",
    "linebet.com",
    "linebet.com.ng",
    "linebet.ng",
    "livescorebet.com",
    "luckybandit.com",
    "marathonbet.com",
    "mbitcasino.com",
    "megapari.com",
    "megapari.ng",
    "melbet.com",
    "melbet.com.gh",
    "melbet.ng",
    "merrybet.com",
    "metaspins.com",
    "mostbet.com",
    "mostbet.ng",
    "mrgreen.com",
    "msport.com",
    "msport.com.ng",
    "msport.ng",
    "mybookie.ag",
    "mylottohub.com",
    "naijabet.com",
    "nairabet.com",
    "nairabet.ng",
    "nairastake.com",
    "nairastars.com",
    "neds.com.au",
    "novig.com",
    "paddypower.com",
    "paddypower.ie",
    "parimatch.co.tz",
    "parimatch.com",
    "parimatch.in",
    "parimatch.ng",
    "paripesa.com",
    "partypoker.com",
    "pinnacle.com",
    "pointsbet.com",
    "pointsbet.com.au",
    "pokerstars.com",
    "pokerstars.eu",
    "poolbet365.com",
    "premierbet.co.ao",
    "premierbet.co.cm",
    "premierbet.co.ga",
    "premierbet.com",
    "premierbet.com.ng",
    "prizepicks.com",
    "prophetx.co",
    "rain.bg",
    "rainbet.com",
    "rollbit.com",
    "rollbit.gg",
    "roobet.com",
    "sbobet.com",
    "shuffle.com",
    "skybet.com",
    "skybet.ie",
    "sleeper.com",
    "slots.lv",
    "spinpalace.com",
    "sportingbet.com",
    "sportingbet.com.au",
    "sportpesa.com",
    "sportsbet.com.au",
    "sportsbet.io",
    "sporty.net",
    "sportybet.app",
    "sportybet.co",
    "sportybet.com",
    "sportybet.net",
    "sportybet.ng",
    "sportydog.net",
    "stake.ac",
    "stake.bet",
    "stake.com",
    "stake.games",
    "stake.us",
    "sugarhouse.com",
    "supabets.co.za",
    "supabets.com",
    "surebet247.com",
    "sureodds.ng",
    "tab.com.au",
    "thescore.bet",
    "thunderpick.com",
    "thunderpick.io",
    "tipico.com",
    "tipico.de",
    "tipico.us",
    "twinspires.com",
    "tz.betika.com",
    "ug.betika.com",
    "underdogfantasy.com",
    "unibet.com",
    "vave.com",
    "wild.io",
    "williamhill.com",
    "williamhill.es",
    "williamhill.it",
    "williamhill.us",
    "winnersgoldenbet.com"
  ]

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

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    verifyScreenTimeShieldAfterForeground(reason: "applicationDidBecomeActive")
  }

  private func handleBlockerCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    logShield("method=\(call.method)")

    switch call.method {
    case "requestVpnPermission":
      enableFullProtection { outcome in
        self.finishProtectionMethod(call.method, outcome: outcome, successValue: "vpn_enabled", result: result)
      }

    case "startVpn":
      enableFullProtection { outcome in
        self.finishProtectionMethod(call.method, outcome: outcome, successValue: "vpn_started", result: result)
      }

    case "enableContentFilter", "enableWebsiteShield":
      // Legacy channel name from the content-filter era. Now enables the
      // App Store-safe website shield (packet tunnel DNS, DNS Settings fallback).
      enableWebsiteShield { outcome in
        self.finishWebsiteShieldMethod(call.method, outcome: outcome, successValue: "enabled", result: result)
      }

    case "requestScreenTimeAuthorization":
      requestScreenTimeAuthorization { success, error in
        self.logScreenTime("method=\(call.method) authorization success=\(success) error=\(self.describeError(error, stage: "requestScreenTimeAuthorization"))")
        if success {
          result("already_granted")
        } else {
          let errorDescription = self.describeError(error, stage: "enableWebsiteShield")
          result(
            FlutterError(
              code: "website_shield_enable_failed",
              message: errorDescription,
              details: errorDescription
            )
          )
        }
      }

    case "enableScreenTimeShield":
      enableScreenTimeShield { success, error in
        self.logScreenTime("method=\(call.method) enable success=\(success) error=\(self.describeError(error, stage: "enableScreenTimeShield"))")
        if success {
          result("enabled")
        } else {
          let errorDescription = self.describeError(error, stage: "enableScreenTimeShield")
          result(
            FlutterError(
              code: "screen_time_shield_enable_failed",
              message: errorDescription,
              details: errorDescription
            )
          )
        }
      }

    case "stopVpn":
      disableWebsiteShield { success, error in
        if success {
          result("stopped")
        } else {
          result(
            FlutterError(
              code: "website_shield_disable_failed",
              message: error?.localizedDescription ?? "Website shield could not be disabled.",
              details: nil
            )
          )
        }
      }

    case "disableScreenTimeShield":
      disableScreenTimeShield { success, error in
        if success {
          result("disabled")
        } else {
          result(
            FlutterError(
              code: "screen_time_shield_disable_failed",
              message: error?.localizedDescription ?? "Screen Time shield could not be disabled.",
              details: nil
            )
          )
        }
      }

    case "isVpnPermissionGranted":
      isWebsiteShieldEnabled { enabled, mode in
        self.logShield("protection readiness websiteShield=\(enabled) mode=\(mode) screenTime=\(self.isScreenTimeAuthorized())")
        result(enabled)
      }

    case "getScreenTimeAuthorizationStatus":
      result(isScreenTimeAuthorized())

    case "runManagedWebContentSingleDomainTest":
      runManagedWebContentSingleDomainTest(useShield: false) { success, error in
        if success {
          result("blocked_by_filter_example_com_applied")
        } else {
          let errorDescription = self.describeError(error, stage: "runManagedWebContentSingleDomainTest")
          result(
            FlutterError(
              code: "managed_web_content_test_failed",
              message: errorDescription,
              details: errorDescription
            )
          )
        }
      }

    case "runManagedWebDomainShieldSingleDomainTest":
      runManagedWebContentSingleDomainTest(useShield: true) { success, error in
        if success {
          result("shield_web_domains_example_com_applied")
        } else {
          let errorDescription = self.describeError(error, stage: "runManagedWebDomainShieldSingleDomainTest")
          result(
            FlutterError(
              code: "managed_web_domain_shield_test_failed",
              message: errorDescription,
              details: errorDescription
            )
          )
        }
      }

    case "getWebsiteShieldDiagnostics":
      websiteShieldDiagnostics { diagnostics in
        result(diagnostics)
      }

    case "selectScreenTimeTargets", "openFamilyActivityPicker":
      presentFamilyActivityPicker(result: result)

    case "getAppleSubscriptionStatus":
      getAppleSubscriptionStatus { status in
        result(status)
      }

    case "getNativeVpnInterrupted":
      let defaults = UserDefaults(suiteName: appGroupId)
      let interrupted = defaults?.bool(forKey: "vpn_interrupted") ?? false
      result(interrupted)

    case "syncBlockState":
      syncBlockState(arguments: call.arguments)
      result(nil)

    case "setDnsDebugLogging":
      setDnsDebugLogging(arguments: call.arguments)
      result(nil)

    case "getDnsDebugEvents":
      result(getDnsDebugEvents(arguments: call.arguments))

    case "clearDnsDebugEvents":
      clearDnsDebugEvents()
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

  private enum WebsiteShieldOutcome {
    case active(mode: String)
    case needsDNSActivation
    case failed(Error?)
  }

  private enum FullProtectionOutcome {
    case active(mode: String)
    case needsDNSActivation
    case screenTimeFailed(Error?)
    case websiteShieldFailed(Error?)
  }

  /// Screen Time apps first, then website DNS shield (tunnel → DNS Settings fallback).
  private func enableFullProtection(completion: @escaping (FullProtectionOutcome) -> Void) {
    enableScreenTimeShield { screenTimeSuccess, screenTimeError in
      self.logScreenTime(
        "enableFullProtection screen-time success=\(screenTimeSuccess) error=\(self.describeError(screenTimeError, stage: "enableScreenTimeShield"))"
      )
      guard screenTimeSuccess else {
        completion(.screenTimeFailed(screenTimeError))
        return
      }

      self.enableWebsiteShield { outcome in
        switch outcome {
        case .active(let mode):
          completion(.active(mode: mode))
        case .needsDNSActivation:
          completion(.needsDNSActivation)
        case .failed(let error):
          completion(.websiteShieldFailed(error))
        }
      }
    }
  }

  /// Primary: packet-tunnel forcing AdGuard DoH.
  /// Fallback: NEDNSSettingsManager DoH profile (no VPN icon; may need manual DNS select).
  private func enableWebsiteShield(completion: @escaping (WebsiteShieldOutcome) -> Void) {
    logShield(
      "website-shield enable begin bundle=\(Bundle.main.bundleIdentifier ?? "<nil>") primary=packet-tunnel-adguard fallback=dns-settings"
    )

    enableTunnelShield { tunnelSuccess, tunnelError in
      if tunnelSuccess {
        self.logShield("website-shield active via packet-tunnel")
        if self.isScreenTimeAuthorized() {
          let counts = self.applyScreenTimeShieldSettings()
          self.logScreenTime(
            "packet-tunnel enable also re-applied Screen Time appCount=\(counts.appCount) webDomainCount=\(counts.webDomainCount)"
          )
        }
        completion(.active(mode: "packet-tunnel"))
        return
      }

      self.logShield(
        "packet-tunnel failed; trying dns-settings fallback error=\(self.describeError(tunnelError, stage: "enablePacketTunnel"))"
      )

      self.enableDNSSettings { dnsSuccess, dnsError in
        if !dnsSuccess {
          self.logShield(
            "dns-settings fallback failed error=\(self.describeError(dnsError, stage: "enableDNSSettings"))"
          )
          // Prefer the tunnel error if both failed — more actionable for VPN capability issues.
          completion(.failed(tunnelError ?? dnsError))
          return
        }

        self.isDNSSettingsEnabled { enabled in
          if enabled {
            self.logShield("website-shield active via dns-settings")
            completion(.active(mode: "dns-settings"))
          } else {
            self.logShield("dns-settings installed but not selected in iOS Settings")
            completion(.needsDNSActivation)
          }
        }
      }
    }
  }

  private func finishProtectionMethod(
    _ method: String,
    outcome: FullProtectionOutcome,
    successValue: String,
    result: @escaping FlutterResult
  ) {
    switch outcome {
    case .active(let mode):
      self.logShield("method=\(method) full-protection success mode=\(mode)")
      result(successValue)
    case .needsDNSActivation:
      self.logShield("method=\(method) dns_settings_needs_activation")
      result("dns_settings_needs_activation")
    case .screenTimeFailed(let error):
      let errorDescription = self.describeError(error, stage: "enableScreenTimeShield")
      self.logScreenTime("method=\(method) screen-time failed \(errorDescription)")
      result(
        FlutterError(
          code: "screen_time_shield_enable_failed",
          message: errorDescription,
          details: errorDescription
        )
      )
    case .websiteShieldFailed(let error):
      let errorDescription = self.describeError(error, stage: "enableWebsiteShield")
      self.logShield("method=\(method) website-shield failed \(errorDescription)")
      result(
        FlutterError(
          code: "website_shield_enable_failed",
          message: errorDescription,
          details: errorDescription
        )
      )
    }
  }

  private func finishWebsiteShieldMethod(
    _ method: String,
    outcome: WebsiteShieldOutcome,
    successValue: String,
    result: @escaping FlutterResult
  ) {
    switch outcome {
    case .active(let mode):
      self.logShield("method=\(method) success mode=\(mode)")
      result(successValue)
    case .needsDNSActivation:
      self.logShield("method=\(method) dns_settings_needs_activation")
      result("dns_settings_needs_activation")
    case .failed(let error):
      let errorDescription = self.describeError(error, stage: "enableWebsiteShield")
      self.logShield("method=\(method) failed \(errorDescription)")
      result(
        FlutterError(
          code: "website_shield_enable_failed",
          message: errorDescription,
          details: errorDescription
        )
      )
    }
  }

  /// Enables the AdGuard DNS packet tunnel. Removes any DNS Settings profile
  /// first so the two mechanisms cannot fight over system DNS.
  private func enableTunnelShield(completion: @escaping (Bool, Error?) -> Void) {
    removeDomainScopedDNSSettings { removed, removeError in
      self.logShield(
        "dns-settings profile cleanup before tunnel removed=\(removed) error=\(self.describeError(removeError, stage: "removeLegacyDNSSettings"))"
      )
      self.enablePacketTunnel(completion: completion)
    }
  }

  private func enableDNSSettings(completion: @escaping (Bool, Error?) -> Void) {
    // A leftover BetControl packet tunnel VPN takes DNS precedence over
    // NEDNSSettingsManager and forwards queries to 1.1.1.1/8.8.8.8, so AdGuard
    // never sees any traffic. Remove any stale profile first.
    removeStalePacketTunnelProfiles {
      self.enableDNSSettingsAfterCleanup(completion: completion)
    }
  }

  private func removeStalePacketTunnelProfiles(completion: @escaping () -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error {
        self.logShield("packet-tunnel cleanup load error=\(self.describeError(error, stage: "removeStalePacketTunnelProfiles"))")
        completion()
        return
      }

      let stale = (managers ?? []).filter {
        self.isConfiguredPacketTunnel($0) || $0.localizedDescription == self.packetTunnelDescription
      }

      guard !stale.isEmpty else {
        completion()
        return
      }

      let group = DispatchGroup()
      for manager in stale {
        group.enter()
        manager.connection.stopVPNTunnel()
        manager.removeFromPreferences { removeError in
          if let removeError {
            self.logShield("packet-tunnel cleanup remove error=\(self.describeError(removeError, stage: "removeStalePacketTunnelProfile"))")
          } else {
            self.logShield("packet-tunnel cleanup removed profile \(manager.localizedDescription ?? "<unnamed>")")
          }
          group.leave()
        }
      }
      group.notify(queue: .main) {
        completion()
      }
    }
  }

  private func enableDNSSettingsAfterCleanup(completion: @escaping (Bool, Error?) -> Void) {
    guard let serverURL = URL(string: dnsSettingsDoHURL) else {
      let error = NSError(
        domain: "BetControlDNSSettings",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Invalid BetControl DNS-over-HTTPS URL."]
      )
      DispatchQueue.main.async { completion(false, error) }
      return
    }

    let manager = NEDNSSettingsManager.shared()
    logShield("dns-settings load begin dohURL=\(dnsSettingsDoHURL) bootstrapServers=\(dnsSettingsBootstrapServers) matchDomains=\(dnsSettingsMatchDomains)")

    manager.loadFromPreferences { error in
      if let error {
        self.logShield("dns-settings load error=\(self.describeError(error, stage: "loadDNSSettingsPreferences"))")
        DispatchQueue.main.async { completion(false, error) }
        return
      }

      let settings = NEDNSOverHTTPSSettings(servers: self.dnsSettingsBootstrapServers)
      settings.serverURL = serverURL
      settings.matchDomains = self.dnsSettingsMatchDomains
      settings.matchDomainsNoSearch = true

      manager.localizedDescription = self.dnsSettingsDescription
      manager.dnsSettings = settings
      manager.onDemandRules = nil

      self.logShield("dns-settings save begin \(self.describeDNSSettingsManager(manager))")
      manager.saveToPreferences { saveError in
        if let saveError {
          if self.isConfigurationUnchanged(saveError) {
            self.logShield("dns-settings save unchanged; reloading current profile")
            manager.loadFromPreferences { reloadError in
              if let reloadError {
                self.logShield("dns-settings unchanged reload error=\(self.describeError(reloadError, stage: "reloadUnchangedDNSSettingsPreferences"))")
                DispatchQueue.main.async { completion(false, reloadError) }
              } else {
                self.logShield("dns-settings unchanged reload \(self.describeDNSSettingsManager(manager))")
                DispatchQueue.main.async { completion(self.isConfiguredDNSSettings(manager), nil) }
              }
            }
            return
          }
          self.logShield("dns-settings save error=\(self.describeError(saveError, stage: "saveDNSSettingsPreferences"))")
          DispatchQueue.main.async { completion(false, saveError) }
          return
        }

        manager.loadFromPreferences { verifyError in
          if let verifyError {
            self.logShield("dns-settings verify load error=\(self.describeError(verifyError, stage: "verifyDNSSettingsPreferences"))")
          } else {
            self.logShield("dns-settings verify \(self.describeDNSSettingsManager(manager))")
          }
          DispatchQueue.main.async {
            completion(verifyError == nil && self.isConfiguredDNSSettings(manager), verifyError)
          }
        }
      }
    }
  }

  private func disableDNSSettings(completion: @escaping (Bool, Error?) -> Void) {
    let manager = NEDNSSettingsManager.shared()
    logShield("dns-settings disable begin")
    manager.loadFromPreferences { _ in
      manager.removeFromPreferences { error in
        if let error, !self.isMissingConfiguration(error) {
          self.logShield("dns-settings disable error=\(self.describeError(error, stage: "removeDNSSettingsPreferences"))")
          DispatchQueue.main.async { completion(false, error) }
        } else {
          self.logShield("dns-settings disable success")
          DispatchQueue.main.async { completion(true, nil) }
        }
      }
    }
  }

  private func isDNSSettingsEnabled(completion: @escaping (Bool) -> Void) {
    let manager = NEDNSSettingsManager.shared()
    manager.loadFromPreferences { error in
      if let error {
        self.logShield("dns-settings status load error=\(self.describeError(error, stage: "isDNSSettingsEnabled"))")
        DispatchQueue.main.async { completion(false) }
        return
      }

      let configured = self.isConfiguredDNSSettings(manager)
      let enabled = configured && manager.isEnabled
      self.logShield("dns-settings status enabled=\(enabled) configured=\(configured) \(self.describeDNSSettingsManager(manager))")
      DispatchQueue.main.async { completion(enabled) }
    }
  }

  private func enablePacketTunnel(completion: @escaping (Bool, Error?) -> Void) {
    logShield("packet-tunnel enable begin provider=\(packetTunnelExtensionBundleId) appGroup=\(appGroupId)")
    loadPacketTunnelManager { manager, error in
      if let error {
        self.logShield("packet-tunnel load error=\(self.describeError(error, stage: "loadPacketTunnelPreferences"))")
        DispatchQueue.main.async { completion(false, error) }
        return
      }

      guard let manager else {
        let error = NSError(
          domain: "BetControlPacketTunnel",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Could not create Website Shield VPN configuration."]
        )
        DispatchQueue.main.async { completion(false, error) }
        return
      }

      self.configurePacketTunnelManager(manager)
      self.logShield("packet-tunnel save begin \(self.describePacketTunnelManager(manager))")

      manager.saveToPreferences { saveError in
        if let saveError {
          // First-time install can also surface as "unchanged" if profile already exists.
          if !self.isConfigurationUnchanged(saveError) {
            self.logShield("packet-tunnel save error=\(self.describeError(saveError, stage: "savePacketTunnelPreferences"))")
            DispatchQueue.main.async { completion(false, saveError) }
            return
          }
          self.logShield("packet-tunnel save unchanged; continuing to load/start")
        }

        // Must reload after save before startVPNTunnel — Apple requires this.
        manager.loadFromPreferences { loadError in
          if let loadError {
            self.logShield("packet-tunnel verify load error=\(self.describeError(loadError, stage: "verifyPacketTunnelPreferences"))")
            DispatchQueue.main.async { completion(false, loadError) }
            return
          }

          // Ensure enabled after reload (some iOS versions leave the profile disabled).
          if !manager.isEnabled || !manager.isOnDemandEnabled {
            self.configurePacketTunnelManager(manager)
            manager.saveToPreferences { reSaveError in
              if let reSaveError, !self.isConfigurationUnchanged(reSaveError) {
                self.logShield("packet-tunnel re-enable save error=\(self.describeError(reSaveError, stage: "reEnablePacketTunnel"))")
                DispatchQueue.main.async { completion(false, reSaveError) }
                return
              }
              manager.loadFromPreferences { _ in
                self.startPacketTunnelConnection(manager, completion: completion)
              }
            }
            return
          }

          self.startPacketTunnelConnection(manager, completion: completion)
        }
      }
    }
  }

  private func startPacketTunnelConnection(
    _ manager: NETunnelProviderManager,
    completion: @escaping (Bool, Error?) -> Void
  ) {
    let status = manager.connection.status
    if status == .connected || status == .connecting || status == .reasserting {
      self.logShield("packet-tunnel already active status=\(self.vpnStatusDescription(status))")
      self.waitForPacketTunnelReady(manager, attempt: 0, completion: completion)
      return
    }

    do {
      self.logShield("packet-tunnel start begin \(self.describePacketTunnelManager(manager))")
      try manager.connection.startVPNTunnel()
      self.logShield("packet-tunnel start requested status=\(self.vpnStatusDescription(manager.connection.status))")
      self.waitForPacketTunnelReady(manager, attempt: 0, completion: completion)
    } catch {
      self.logShield("packet-tunnel start error=\(self.describeError(error, stage: "startPacketTunnel"))")
      if self.isVPNConfigurationStale(error) {
        self.loadPacketTunnelManager { refreshedManager, refreshError in
          if let refreshError {
            DispatchQueue.main.async { completion(false, refreshError) }
            return
          }
          guard let refreshedManager else {
            DispatchQueue.main.async { completion(false, error) }
            return
          }

          do {
            self.configurePacketTunnelManager(refreshedManager)
            try refreshedManager.connection.startVPNTunnel()
            self.waitForPacketTunnelReady(refreshedManager, attempt: 0, completion: completion)
          } catch {
            DispatchQueue.main.async { completion(false, error) }
          }
        }
      } else {
        DispatchQueue.main.async { completion(false, error) }
      }
    }
  }

  /// Poll until the tunnel is fully connected (DNS is only forced when connected).
  private func waitForPacketTunnelReady(
    _ manager: NETunnelProviderManager,
    attempt: Int,
    completion: @escaping (Bool, Error?) -> Void
  ) {
    let maxAttempts = 30 // ~15s at 0.5s
    let status = manager.connection.status
    let connected = manager.isEnabled &&
      isConfiguredPacketTunnel(manager) &&
      (status == .connected || status == .reasserting)

    if connected {
      logShield("packet-tunnel ready status=\(vpnStatusDescription(status)) attempt=\(attempt)")
      DispatchQueue.main.async { completion(true, nil) }
      return
    }

    // Still bringing the extension up — keep waiting.
    if attempt < maxAttempts &&
        (status == .connecting || status == .reasserting || status == .disconnected) {
      if attempt == 0 || attempt % 4 == 0 {
        logShield("packet-tunnel waiting status=\(vpnStatusDescription(status)) attempt=\(attempt)")
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        manager.loadFromPreferences { _ in
          self.waitForPacketTunnelReady(manager, attempt: attempt + 1, completion: completion)
        }
      }
      return
    }

    let error = NSError(
      domain: "BetControlPacketTunnel",
      code: 2,
      userInfo: [
        NSLocalizedDescriptionKey:
          "Website Shield VPN did not connect (status=\(vpnStatusDescription(status))). Check Settings > VPN and allow BetControl."
      ]
    )
    logShield("packet-tunnel not ready after wait status=\(vpnStatusDescription(status))")
    DispatchQueue.main.async { completion(false, error) }
  }

  private func disablePacketTunnel(completion: @escaping (Bool, Error?) -> Void) {
    logShield("packet-tunnel disable begin")
    loadPacketTunnelManager { manager, error in
      if let error {
        self.logShield("packet-tunnel disable load error=\(self.describeError(error, stage: "loadPacketTunnelForDisable"))")
        DispatchQueue.main.async { completion(false, error) }
        return
      }

      guard let manager, self.isConfiguredPacketTunnel(manager) else {
        // No BetControl tunnel configuration installed — nothing to disable.
        DispatchQueue.main.async { completion(true, nil) }
        return
      }

      manager.isOnDemandEnabled = false
      manager.onDemandRules = nil
      manager.isEnabled = false
      manager.connection.stopVPNTunnel()
      manager.saveToPreferences { saveError in
        if let saveError {
          self.logShield("packet-tunnel disable save error=\(self.describeError(saveError, stage: "disablePacketTunnel"))")
        } else {
          self.logShield("packet-tunnel disable save success")
        }
        DispatchQueue.main.async { completion(saveError == nil, saveError) }
      }
    }
  }

  private func isPacketTunnelEnabled(completion: @escaping (Bool) -> Void) {
    loadPacketTunnelManager { manager, error in
      if let error {
        self.logShield("packet-tunnel status load error=\(self.describeError(error, stage: "isPacketTunnelEnabled"))")
        completion(false)
        return
      }

      guard let manager else {
        self.logShield("packet-tunnel status missing")
        completion(false)
        return
      }

      let status = manager.connection.status
      // "connecting" alone is not enough — DNS override only applies when connected.
      let ready = manager.isEnabled && self.isConfiguredPacketTunnel(manager) &&
        (status == .connected || status == .reasserting)
      self.logShield("packet-tunnel status ready=\(ready) \(self.describePacketTunnelManager(manager))")
      completion(ready)
    }
  }

  private func loadPacketTunnelManager(completion: @escaping (NETunnelProviderManager?, Error?) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error {
        completion(nil, error)
        return
      }

      let existing = managers?.first { self.isConfiguredPacketTunnel($0) || $0.localizedDescription == self.packetTunnelDescription }
      completion(existing ?? NETunnelProviderManager(), nil)
    }
  }

  private func configurePacketTunnelManager(_ manager: NETunnelProviderManager) {
    let providerProtocol = NETunnelProviderProtocol()
    providerProtocol.providerBundleIdentifier = packetTunnelExtensionBundleId
    providerProtocol.serverAddress = "BetControl Local DNS Shield"
    providerProtocol.providerConfiguration = [
      "appGroupId": appGroupId,
      "dnsMode": "local-sinkhole",
      "configurationVersion": 3
    ]

    manager.localizedDescription = packetTunnelDescription
    manager.protocolConfiguration = providerProtocol
    manager.isEnabled = true
    // On-demand keeps the shield sticky: iOS reconnects the tunnel
    // automatically after reboots, network changes, or manual disconnects.
    manager.isOnDemandEnabled = true
    manager.onDemandRules = [NEOnDemandRuleConnect()]
  }

  private func isConfiguredPacketTunnel(_ manager: NETunnelProviderManager) -> Bool {
    guard let providerProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol else {
      return false
    }
    return providerProtocol.providerBundleIdentifier == packetTunnelExtensionBundleId
  }

  private func disableWebsiteShield(completion: @escaping (Bool, Error?) -> Void) {
    logShield("website-shield disable begin (packet-tunnel + dns-settings)")
    disablePacketTunnel { tunnelSuccess, tunnelError in
      self.disableDNSSettings { dnsSuccess, dnsError in
        let success = tunnelSuccess && dnsSuccess
        let error = tunnelError ?? dnsError
        if success {
          self.logShield("website-shield disable success")
        } else {
          self.logShield(
            "website-shield disable partial/failure tunnelOk=\(tunnelSuccess) dnsOk=\(dnsSuccess) error=\(self.describeError(error, stage: "disableWebsiteShield"))"
          )
        }
        completion(success, error)
      }
    }
  }

  /// True when either the AdGuard packet tunnel or the DNS Settings profile is active.
  private func isWebsiteShieldEnabled(completion: @escaping (Bool, String) -> Void) {
    isPacketTunnelEnabled { tunnelReady in
      if tunnelReady {
        completion(true, "packet-tunnel")
        return
      }
      self.isDNSSettingsEnabled { dnsReady in
        completion(dnsReady, dnsReady ? "dns-settings" : "none")
      }
    }
  }

  private func websiteShieldDiagnostics(completion: @escaping ([String: Any]) -> Void) {
    loadPacketTunnelManager { tunnelManager, tunnelError in
      let dnsSettingsManager = NEDNSSettingsManager.shared()
      dnsSettingsManager.loadFromPreferences { dnsSettingsError in
        let selection = self.loadFamilyActivitySelection()
        let managedDomainNames = self.managedWebDomainNames()
        let selectedWebDomainTokenCount = selection.webDomainTokens.count
        let probeDomains = ["sportybet.com", "sportybet.ng", "bet9ja.com", "1xbet.com"]
        var probePresence: [String: Bool] = [:]
        for domain in probeDomains {
          probePresence[domain] = managedDomainNames.contains(domain)
        }

        let tunnelStatus = tunnelManager?.connection.status
        let tunnelReady = tunnelManager.map {
          $0.isEnabled && self.isConfiguredPacketTunnel($0) &&
            (tunnelStatus == .connected || tunnelStatus == .reasserting)
        } ?? false
        let tunnelConnecting = tunnelManager.map {
          $0.isEnabled && self.isConfiguredPacketTunnel($0) && tunnelStatus == .connecting
        } ?? false

        let dnsConfigured = self.isConfiguredDNSSettings(dnsSettingsManager)
        let dnsEnabled = dnsConfigured && dnsSettingsManager.isEnabled && dnsSettingsError == nil

        let enforcementMode: String
        let shieldType: String
        if tunnelReady {
          enforcementMode = "local-dns-sinkhole-active"
          shieldType = "packet-tunnel-local-dns"
        } else if tunnelConnecting {
          enforcementMode = "local-dns-sinkhole-connecting"
          shieldType = "packet-tunnel-local-dns"
        } else if dnsEnabled {
          enforcementMode = "dns-settings-adguard-active"
          shieldType = "dns-settings-adguard"
        } else if dnsConfigured {
          enforcementMode = "dns-settings-needs-activation"
          shieldType = "dns-settings-adguard"
        } else {
          enforcementMode = "website-shield-not-active"
          shieldType = "none"
        }

        var diagnostics: [String: Any] = [
          "appBundleIdentifier": Bundle.main.bundleIdentifier ?? NSNull(),
          "appGroupId": self.appGroupId,
          "pluginExists": self.dnsExtensionBundleExists(),
          "websiteShieldType": shieldType,
          "websiteShieldEnforcementMode": enforcementMode,
          "expectedDNSSettingsURL": self.dnsSettingsDoHURL,
          "expectedDNSSettingsBootstrapServers": self.dnsSettingsBootstrapServers,
          "expectedDNSSettingsMatchDomains": self.dnsSettingsMatchDomains,
          "expectedDNSSettingsMatchDomainsDebug": self.describeMatchDomains(self.dnsSettingsMatchDomains),
          "screenTimeAuthorizationStatus": self.screenTimeAuthorizationStatusDescription(),
          "screenTimeAuthorized": self.isScreenTimeAuthorized(),
          "screenTimeBlockedAppCount": self.blockedAppBundleIdentifiers.count,
          "screenTimeBlockedDomainCount": self.blockedWebDomains.count,
          "screenTimeManagedWebDomainCount": managedDomainNames.count,
          "screenTimeSelectedApplicationTokenCount": selection.applicationTokens.count,
          "screenTimeSelectedCategoryTokenCount": selection.categoryTokens.count,
          "screenTimeSelectedWebDomainTokenCount": selectedWebDomainTokenCount,
          "screenTimeBlockedDomains": self.blockedWebDomains.sorted(),
          "screenTimeManagedWebDomains": managedDomainNames,
          "screenTimeProbeDomainPresence": probePresence
        ]

        if let tunnelError {
          diagnostics["packetTunnelLoadError"] = self.describeError(tunnelError, stage: "diagnostics.packetTunnel.load")
        } else if let tunnelManager {
          diagnostics["packetTunnelManager"] = self.packetTunnelManagerDiagnostics(tunnelManager)
        }

        if let dnsSettingsError {
          diagnostics["dnsSettingsLoadError"] = self.describeError(dnsSettingsError, stage: "diagnostics.dnsSettings.load")
        } else {
          diagnostics["dnsSettingsManager"] = self.dnsSettingsManagerDiagnostics(dnsSettingsManager)
        }

        self.logShield("diagnostics \(diagnostics)")
        completion(diagnostics)
      }
    }
  }

  private func removeDomainScopedDNSSettings(completion: @escaping (Bool, Error?) -> Void) {
    NEDNSSettingsManager.shared().loadFromPreferences { _ in
      NEDNSSettingsManager.shared().removeFromPreferences { settingsError in
        completion(settingsError == nil || self.isMissingConfiguration(settingsError), settingsError)
      }
    }
  }

  private func isConfiguredDNSSettings(_ manager: NEDNSSettingsManager) -> Bool {
    guard let settings = manager.dnsSettings else { return false }
    guard isSystemWideMatchDomain(settings.matchDomains) else { return false }
    if let httpsSettings = settings as? NEDNSOverHTTPSSettings {
      return httpsSettings.serverURL?.absoluteString == dnsSettingsDoHURL
    }
    return false
  }

  private func isSystemWideMatchDomain(_ domains: [String]?) -> Bool {
    domains?.count == 1 && domains?.first == ""
  }

  private func describeMatchDomains(_ domains: [String]?) -> [String] {
    guard let domains else { return [] }
    return domains.map { $0.isEmpty ? "<empty-string>" : $0 }
  }

  private func dnsExtensionBundleExists() -> Bool {
    guard let pluginsURL = Bundle.main.builtInPlugInsURL else { return false }
    let extensionURL = pluginsURL.appendingPathComponent("DNSFilterExtension.appex")
    return FileManager.default.fileExists(atPath: extensionURL.path)
  }

  private func isMissingConfiguration(_ error: Error?) -> Bool {
    guard let error = error else { return false }
    return error.localizedDescription.lowercased().contains("configuration does not exist")
  }

  private func isConfigurationUnchanged(_ error: Error?) -> Bool {
    guard let error = error else { return false }
    return error.localizedDescription.lowercased().contains("configuration is unchanged")
  }

  private func isVPNConfigurationStale(_ error: Error?) -> Bool {
    guard let error = error as NSError? else { return false }
    return error.domain == NEVPNErrorDomain && error.code == NEVPNError.configurationStale.rawValue
  }

  private func describeError(_ error: Error?, stage: String) -> String {
    guard let error = error else {
      return "\(stage): Website shield could not be enabled."
    }

    let nsError = error as NSError
    return "\(stage): \(nsError.domain) code \(nsError.code) - \(nsError.localizedDescription)"
  }

  private func describeDNSSettingsManager(_ manager: NEDNSSettingsManager) -> String {
    dnsSettingsManagerDiagnostics(manager)
      .map { "\($0.key)=\($0.value)" }
      .sorted()
      .joined(separator: " ")
  }

  private func dnsSettingsManagerDiagnostics(_ manager: NEDNSSettingsManager) -> [String: Any] {
    let settings = manager.dnsSettings
    let httpsSettings = settings as? NEDNSOverHTTPSSettings
    return [
      "localizedDescription": manager.localizedDescription ?? NSNull(),
      "isEnabled": manager.isEnabled,
      "dnsProtocol": settings.map { "\($0.dnsProtocol.rawValue)" } ?? NSNull(),
      "servers": settings?.servers ?? [],
      "matchDomains": settings?.matchDomains ?? NSNull(),
      "matchDomainsDebug": describeMatchDomains(settings?.matchDomains),
      "matchDomainsCount": settings?.matchDomains?.count ?? NSNull(),
      "matchDomainsNoSearch": settings?.matchDomainsNoSearch ?? NSNull(),
      "hasSystemWideMatchDomain": isSystemWideMatchDomain(settings?.matchDomains),
      "serverURL": httpsSettings?.serverURL?.absoluteString ?? NSNull(),
      "isConfiguredForBetControl": isConfiguredDNSSettings(manager)
    ]
  }

  private func describePacketTunnelManager(_ manager: NETunnelProviderManager) -> String {
    packetTunnelManagerDiagnostics(manager)
      .map { "\($0.key)=\($0.value)" }
      .sorted()
      .joined(separator: " ")
  }

  private func packetTunnelManagerDiagnostics(_ manager: NETunnelProviderManager) -> [String: Any] {
    let provider = manager.protocolConfiguration as? NETunnelProviderProtocol
    return [
      "localizedDescription": manager.localizedDescription ?? NSNull(),
      "isEnabled": manager.isEnabled,
      "isOnDemandEnabled": manager.isOnDemandEnabled,
      "status": vpnStatusDescription(manager.connection.status),
      "providerBundleIdentifier": provider?.providerBundleIdentifier ?? NSNull(),
      "serverAddress": provider?.serverAddress ?? NSNull(),
      "providerConfiguration": provider?.providerConfiguration ?? NSNull(),
      "isConfiguredForBetControl": isConfiguredPacketTunnel(manager)
    ]
  }

  private func vpnStatusDescription(_ status: NEVPNStatus) -> String {
    switch status {
    case .invalid:
      return "invalid"
    case .disconnected:
      return "disconnected"
    case .connecting:
      return "connecting"
    case .connected:
      return "connected"
    case .reasserting:
      return "reasserting"
    case .disconnecting:
      return "disconnecting"
    @unknown default:
      return "unknown"
    }
  }

  private func logShield(_ message: String) {
    NSLog("BetControl WebsiteShield %@", message)
  }

  private func logScreenTime(_ message: String) {
    NSLog("BetControl ScreenTimeShield %@", message)
  }

  private func verifyScreenTimeShieldAfterForeground(reason: String) {
    guard #available(iOS 16.0, *) else {
      logScreenTime("\(reason) skipped; Screen Time shield requires iOS 16+")
      return
    }

    let defaults = UserDefaults(suiteName: appGroupId)
    let isBlocking = defaults?.bool(forKey: "isBlocking") ?? false
    let hasActiveSubscription = defaults?.bool(forKey: "hasActiveSubscription") ?? false
    let unlockTime = defaults?.double(forKey: "unlockTime") ?? 0
    let authorized = isScreenTimeAuthorized()

    logScreenTime(
      "\(reason) verify state isBlocking=\(isBlocking) hasActiveSubscription=\(hasActiveSubscription) authorized=\(authorized) authStatus=\(screenTimeAuthorizationStatusDescription()) unlockTime=\(Int64(unlockTime))"
    )
    logScreenTime(
      "\(reason) note: iOS does not expose a public API for reading the Settings > Screen Time > Content & Privacy Restrictions switch. If web blocking still fails, confirm that switch is ON manually."
    )

    if isBlocking && hasActiveSubscription && authorized {
      let counts = applyScreenTimeShieldSettings()
      logScreenTime(
        "\(reason) re-applied ManagedSettings appCount=\(counts.appCount) webContentCount=\(counts.webDomainCount) hardCommitment=\(self.isHardCommitmentEnabled())"
      )
    } else {
      logScreenTime(
        "\(reason) did not re-apply ManagedSettings because one prerequisite is false"
      )
    }
  }

  private func presentFamilyActivityPicker(result: @escaping FlutterResult) {
    guard #available(iOS 16.0, *) else {
      result(
        FlutterError(
          code: "screen_time_picker_unavailable",
          message: "Screen Time website selection requires iOS 16 or later.",
          details: nil
        )
      )
      return
    }

    guard isScreenTimeAuthorized() else {
      requestScreenTimeAuthorization { success, error in
        if success {
          DispatchQueue.main.async {
            self.presentFamilyActivityPicker(result: result)
          }
        } else {
          result(
            FlutterError(
              code: "screen_time_not_authorized",
              message: error?.localizedDescription ?? "Screen Time permission was not approved.",
              details: nil
            )
          )
        }
      }
      return
    }

    DispatchQueue.main.async {
      guard let presenter = self.topViewController() else {
        result(
          FlutterError(
            code: "screen_time_picker_no_presenter",
            message: "Could not present Screen Time picker.",
            details: nil
          )
        )
        return
      }

      var hostingController: UIViewController?
      let initialSelection = self.loadFamilyActivitySelection()
      let pickerView = BetControlFamilyActivityPickerView(
        initialSelection: initialSelection,
        onCancel: {
          hostingController?.dismiss(animated: true) {
            result([
              "cancelled": true,
              "applicationTokenCount": initialSelection.applicationTokens.count,
              "categoryTokenCount": initialSelection.categoryTokens.count,
              "webDomainTokenCount": initialSelection.webDomainTokens.count
            ])
          }
        },
        onDone: { selection in
          self.saveFamilyActivitySelection(selection)
          let counts = self.applyScreenTimeShieldSettings()
          hostingController?.dismiss(animated: true) {
            result([
              "cancelled": false,
              "applicationTokenCount": selection.applicationTokens.count,
              "categoryTokenCount": selection.categoryTokens.count,
              "webDomainTokenCount": selection.webDomainTokens.count,
              "appliedAppCount": counts.appCount,
              "appliedWebDomainCount": counts.webDomainCount
            ])
          }
        }
      )

      let controller = UIHostingController(rootView: pickerView)
      controller.modalPresentationStyle = .formSheet
      controller.isModalInPresentation = true
      hostingController = controller
      presenter.present(controller, animated: true)
    }
  }

  private func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    let root = scene?.windows.first { $0.isKeyWindow }?.rootViewController
    return topViewController(from: root)
  }

  private func topViewController(from root: UIViewController?) -> UIViewController? {
    if let navigation = root as? UINavigationController {
      return topViewController(from: navigation.visibleViewController)
    }
    if let tab = root as? UITabBarController {
      return topViewController(from: tab.selectedViewController)
    }
    if let presented = root?.presentedViewController {
      return topViewController(from: presented)
    }
    return root
  }

  private func requestScreenTimeAuthorization(completion: @escaping (Bool, Error?) -> Void) {
    guard #available(iOS 16.0, *) else {
      completion(false, NSError(
        domain: "BetControlScreenTime",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Screen Time Shield requires iOS 16 or later."]
      ))
      return
    }

    logScreenTime("authorization begin status=\(screenTimeAuthorizationStatusDescription())")

    Task { @MainActor in
      do {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        let approved = self.isScreenTimeAuthorized()
        self.logScreenTime("authorization finished status=\(self.screenTimeAuthorizationStatusDescription()) approved=\(approved)")
        completion(approved, approved ? nil : NSError(
          domain: "BetControlScreenTime",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Screen Time permission was not approved."]
        ))
      } catch {
        self.logScreenTime("authorization error=\(self.describeError(error, stage: "requestAuthorization"))")
        completion(false, error)
      }
    }
  }

  private func enableScreenTimeShield(completion: @escaping (Bool, Error?) -> Void) {
    guard #available(iOS 16.0, *) else {
      completion(false, NSError(
        domain: "BetControlScreenTime",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Screen Time Shield requires iOS 16 or later."]
      ))
      return
    }

    let applyShield = {
      let counts = self.applyScreenTimeShieldSettings()
      self.logScreenTime("enabled appCount=\(counts.appCount) webContentCount=\(counts.webDomainCount) hardCommitment=\(self.isHardCommitmentEnabled())")
      completion(true, nil)
    }

    if isScreenTimeAuthorized() {
      applyShield()
      return
    }

    requestScreenTimeAuthorization { success, error in
      if success {
        applyShield()
      } else {
        completion(false, error)
      }
    }
  }

  private func disableScreenTimeShield(completion: @escaping (Bool, Error?) -> Void) {
    guard #available(iOS 15.0, *) else {
      completion(true, nil)
      return
    }

    screenTimeStore.application.blockedApplications = nil
    screenTimeStore.application.denyAppRemoval = nil
    screenTimeStore.webContent.blockedByFilter = nil
    screenTimeStore.shield.applications = nil
    screenTimeStore.shield.webDomains = nil
    screenTimeStore.shield.applicationCategories = nil
    screenTimeStore.shield.webDomainCategories = nil
    logScreenTime("disabled and cleared managed settings")
    completion(true, nil)
  }

  private func runManagedWebContentSingleDomainTest(
    useShield: Bool,
    completion: @escaping (Bool, Error?) -> Void
  ) {
    guard #available(iOS 16.0, *) else {
      completion(false, NSError(
        domain: "BetControlScreenTime",
        code: 4,
        userInfo: [NSLocalizedDescriptionKey: "Managed web content testing requires iOS 16 or later."]
      ))
      return
    }

    let applyTest = {
      let exampleDomain = WebDomain(domain: "example.com")
      self.screenTimeStore.application.blockedApplications = nil
      self.screenTimeStore.application.denyAppRemoval = nil
      self.screenTimeStore.webContent.blockedByFilter = nil
      self.screenTimeStore.shield.applications = nil
      self.screenTimeStore.shield.webDomains = nil
      self.screenTimeStore.shield.applicationCategories = nil
      self.screenTimeStore.shield.webDomainCategories = nil

      if useShield {
        let selection = self.loadFamilyActivitySelection()
        guard !selection.webDomainTokens.isEmpty else {
          completion(false, NSError(
            domain: "BetControlScreenTime",
            code: 5,
            userInfo: [
              NSLocalizedDescriptionKey:
                "shield.webDomains requires WebDomainToken values from FamilyActivityPicker. It cannot be set with WebDomain(domain: \"example.com\")."
            ]
          ))
          return
        }

        self.screenTimeStore.shield.webDomains = selection.webDomainTokens
        self.logScreenTime("single-domain shield control applied saved webDomainTokenCount=\(selection.webDomainTokens.count)")
      } else {
        self.screenTimeStore.webContent.blockedByFilter = .specific(Set([exampleDomain]))
        self.logScreenTime("single-domain test applied webContent.blockedByFilter rawDomain=example.com")
      }

      completion(true, nil)
    }

    if isScreenTimeAuthorized() {
      applyTest()
      return
    }

    requestScreenTimeAuthorization { success, error in
      if success {
        applyTest()
      } else {
        completion(false, error)
      }
    }
  }

  private func applyScreenTimeShieldSettings() -> (appCount: Int, webDomainCount: Int) {
    let applications = Set(blockedAppBundleIdentifiers.map { Application(bundleIdentifier: $0) })
    let domainNames = managedWebDomainNames()
    let domains = Set(domainNames.map { WebDomain(domain: $0) })
    let selection = loadFamilyActivitySelection()
    let hardCommitment = isHardCommitmentEnabled()

    screenTimeStore.application.blockedApplications = applications
    // Opt-in only: Apple exposes uninstall lock as device-wide (all apps),
    // not BetControl-only. Default off; set when user enables Hard Commitment.
    screenTimeStore.application.denyAppRemoval = hardCommitment ? true : nil
    screenTimeStore.webContent.blockedByFilter = .specific(domains)
    screenTimeStore.shield.applications = nil
    screenTimeStore.shield.webDomains =
      selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    screenTimeStore.shield.applicationCategories = nil
    screenTimeStore.shield.webDomainCategories = nil
    logManagedWebDomains(domainNames, reason: "apply")
    logManagedWebDomainObjects(domains, reason: "apply")
    logScreenTime(
      "applied curated gambling blocklist appCount=\(applications.count) webContentDomainCount=\(domains.count) shieldWebDomainTokenCount=\(selection.webDomainTokens.count) hardCommitment=\(hardCommitment)"
    )

    return (applications.count, domains.count + selection.webDomainTokens.count)
  }

  private func isHardCommitmentEnabled() -> Bool {
    UserDefaults(suiteName: appGroupId)?.bool(forKey: "hardCommitment") ?? false
  }

  private func loadFamilyActivitySelection() -> FamilyActivitySelection {
    let defaults = UserDefaults(suiteName: appGroupId)
    guard let data = defaults?.data(forKey: familyActivitySelectionKey) else {
      return FamilyActivitySelection()
    }

    do {
      return try PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
    } catch {
      logScreenTime("failed to decode saved FamilyActivitySelection error=\(error.localizedDescription)")
      return FamilyActivitySelection()
    }
  }

  private func saveFamilyActivitySelection(_ selection: FamilyActivitySelection) {
    do {
      let data = try PropertyListEncoder().encode(selection)
      let defaults = UserDefaults(suiteName: appGroupId)
      defaults?.set(data, forKey: familyActivitySelectionKey)
      defaults?.synchronize()
      logScreenTime(
        "saved FamilyActivitySelection app=\(selection.applicationTokens.count) category=\(selection.categoryTokens.count) web=\(selection.webDomainTokens.count)"
      )
    } catch {
      logScreenTime("failed to save FamilyActivitySelection error=\(error.localizedDescription)")
    }
  }

  private func managedWebDomainNames() -> [String] {
    var domains = Set<String>()

    for rawDomain in blockedWebDomains {
      let domain = rawDomain
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

      guard !domain.isEmpty else { continue }
      domains.insert(domain)

      let isInfrastructureHost =
        domain.contains("amazonaws.com") || domain.contains("cloudfront.net")
      guard !isInfrastructureHost else { continue }

      if !domain.hasPrefix("www.") {
        domains.insert("www.\(domain)")
      }
      if !domain.hasPrefix("m.") {
        domains.insert("m.\(domain)")
      }
    }

    return domains.sorted()
  }

  private func logManagedWebDomains(_ domains: [String], reason: String) {
    logScreenTime("blocked domain dump reason=\(reason) count=\(domains.count)")
    for (index, domain) in domains.enumerated() {
      logScreenTime("blockedDomain[\(index)]=\(domain)")
    }
  }

  private func logManagedWebDomainObjects(_ domains: Set<WebDomain>, reason: String) {
    let sortedDomains = domains
      .compactMap { $0.domain }
      .sorted()

    logScreenTime("WebDomain object dump reason=\(reason) count=\(sortedDomains.count)")
    for (index, domain) in sortedDomains.enumerated() {
      logScreenTime("webDomainObject[\(index)].domain=\(domain)")
    }
  }

  private func isScreenTimeAuthorized() -> Bool {
    guard #available(iOS 15.0, *) else { return false }
    switch AuthorizationCenter.shared.authorizationStatus {
    case .approved:
      return true
    default:
      if #available(iOS 26.4, *) {
        return AuthorizationCenter.shared.authorizationStatus == .approvedWithDataAccess
      }
      return false
    }
  }

  private func screenTimeAuthorizationStatusDescription() -> String {
    guard #available(iOS 15.0, *) else { return "unavailable" }
    return AuthorizationCenter.shared.authorizationStatus.description
  }

  private func getAppleSubscriptionStatus(completion: @escaping ([String: Any]) -> Void) {
    guard #available(iOS 15.0, *) else {
      completion(["active": false])
      return
    }

    Task {
      let productIds: Set<String> = [
        "betcontrol_monthly_sub",
        "betcontrol_annual_sub"
      ]

      var bestExpiration: Date?

      for await result in Transaction.currentEntitlements {
        guard case .verified(let transaction) = result else { continue }
        guard productIds.contains(transaction.productID) else { continue }

        if let expirationDate = transaction.expirationDate,
           expirationDate > Date(),
           bestExpiration == nil || expirationDate > bestExpiration! {
          bestExpiration = expirationDate
        }
      }

      if let bestExpiration {
        let sandboxAdjustedExpiration = Date().addingTimeInterval(30 * 24 * 60 * 60)
        completion([
          "active": true,
          "expiryMillis": Int64(sandboxAdjustedExpiration.timeIntervalSince1970 * 1000),
          "storeExpiryMillis": Int64(bestExpiration.timeIntervalSince1970 * 1000)
        ])
      } else {
        completion(["active": false])
      }
    }
  }

  private func syncBlockState(arguments: Any?) {
    guard let args = arguments as? [String: Any] else { return }
    let isBlocking = args["isBlocking"] as? Bool ?? false
    let defaults = UserDefaults(suiteName: appGroupId)
    let previousHasActiveSubscription =
      defaults?.bool(forKey: "hasActiveSubscription") ?? false
    let hasActiveSubscription =
      args["hasActiveSubscription"] as? Bool ?? previousHasActiveSubscription

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

    let hardCommitment = (args["hardCommitment"] as? Bool) ?? false

    defaults?.set(isBlocking, forKey: "isBlocking")
    defaults?.set(hasActiveSubscription, forKey: "hasActiveSubscription")
    defaults?.set(unlockTime, forKey: "unlockTime")
    defaults?.set(isBlocking && hardCommitment, forKey: "hardCommitment")
    NSLog(
      "BetControl DNS sync state isBlocking=%@ hasActiveSubscription=%@ hardCommitment=%@ unlockTime=%.0f",
      isBlocking ? "true" : "false",
      hasActiveSubscription ? "true" : "false",
      (isBlocking && hardCommitment) ? "true" : "false",
      unlockTime
    )
    if let dnsDebugEnabled = args["dnsDebugEnabled"] as? Bool {
      defaults?.set(dnsDebugEnabled, forKey: dnsDebugEnabledKey)
    }
    if !isBlocking {
      defaults?.set(false, forKey: "vpn_interrupted")
      defaults?.set(false, forKey: "hardCommitment")
    }

    if isBlocking && hasActiveSubscription && isScreenTimeAuthorized() {
      let counts = applyScreenTimeShieldSettings()
      logScreenTime(
        "sync applied curated gambling blocklist appCount=\(counts.appCount) webDomainCount=\(counts.webDomainCount) hardCommitment=\(hardCommitment)"
      )
    } else if !isBlocking {
      screenTimeStore.application.blockedApplications = nil
      screenTimeStore.application.denyAppRemoval = nil
      screenTimeStore.webContent.blockedByFilter = nil
      screenTimeStore.shield.applications = nil
      screenTimeStore.shield.webDomains = nil
      screenTimeStore.shield.applicationCategories = nil
      screenTimeStore.shield.webDomainCategories = nil
      logScreenTime("sync cleared managed settings")
    } else {
      logScreenTime(
        "sync did not apply managed settings isBlocking=\(isBlocking) hasActiveSubscription=\(hasActiveSubscription) authorized=\(isScreenTimeAuthorized())"
      )
    }

    defaults?.synchronize()
  }

  private func setDnsDebugLogging(arguments: Any?) {
    let args = arguments as? [String: Any]
    let enabled = args?["enabled"] as? Bool ?? false
    let reset = args?["reset"] as? Bool ?? false

    let defaults = UserDefaults(suiteName: appGroupId)
    defaults?.set(enabled, forKey: dnsDebugEnabledKey)

    if reset {
      defaults?.set([], forKey: dnsDebugEventsKey)
      defaults?.set(0, forKey: dnsDebugSequenceKey)
    }

    defaults?.synchronize()
  }

  private func getDnsDebugEvents(arguments: Any?) -> [[String: Any]] {
    let args = arguments as? [String: Any]
    let afterId = args?["afterId"] as? Int ?? 0
    let defaults = UserDefaults(suiteName: appGroupId)
    let events = defaults?.array(forKey: dnsDebugEventsKey) as? [[String: Any]] ?? []

    return events.filter { event in
      let id = event["id"] as? Int ?? 0
      return id > afterId
    }
  }

  private func clearDnsDebugEvents() {
    let defaults = UserDefaults(suiteName: appGroupId)
    defaults?.set([], forKey: dnsDebugEventsKey)
    defaults?.set(0, forKey: dnsDebugSequenceKey)
    defaults?.synchronize()
  }
}

@available(iOS 16.0, *)
private struct BetControlFamilyActivityPickerView: View {
  @State private var selection: FamilyActivitySelection
  let onCancel: () -> Void
  let onDone: (FamilyActivitySelection) -> Void

  init(
    initialSelection: FamilyActivitySelection,
    onCancel: @escaping () -> Void,
    onDone: @escaping (FamilyActivitySelection) -> Void
  ) {
    _selection = State(initialValue: initialSelection)
    self.onCancel = onCancel
    self.onDone = onDone
  }

  var body: some View {
    NavigationView {
      FamilyActivityPicker(
        headerText: "Select the betting apps and websites BetControl should block.",
        footerText: "For websites, select the gambling domains that appear in Screen Time activity.",
        selection: $selection
      )
      .navigationTitle("Blocked Apps & Sites")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            onCancel()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            onDone(selection)
          }
        }
      }
    }
  }
}
