//
//  DNSProxyProvider.swift
//  DNSFilterExtension
//
//  Created by Oluwaferanmi on 15/06/2026.
//

import NetworkExtension
import Foundation
import Network

class DNSProxyProvider: NEDNSProxyProvider {

    // This App Group allows your Flutter UI to send the blocklist to this isolated native extension.
    let sharedDefaults = UserDefaults(suiteName: "group.com.project.betcontrolMain")

    override func startProxy(options: [String: Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
        NSLog("BetControl: DNS Proxy Started")
        completionHandler(nil)
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        NSLog("BetControl: DNS Proxy Stopped")
        completionHandler()
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func wake() {
        // Handle wake from sleep if necessary
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        // Until packet parsing/forwarding is implemented, do not take ownership
        // of DNS flows. Returning true here without a response path would
        // blackhole all DNS traffic on the device.
        return false
    }
}
