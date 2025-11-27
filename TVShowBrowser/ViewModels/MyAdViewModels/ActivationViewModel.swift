//
//  ActivationViewModel.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 26/11/25.
//

import Foundation
import UIKit

@MainActor
final class ActivationViewModel: ObservableObject {
    @Published var deviceCode: String = ""
    @Published var userCode: String = ""
    @Published var expiresAt: String = ""
    @Published var activationStatus: String = ""
    
    @Published var isLoading = false
    @Published var errorMessage: String?

    func activateDevice() {
        isLoading = true

        Task {
            do {
                let payload = ActivationRequest(
                    deviceId: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
                    resolutionWidth: Int(UIScreen.main.bounds.width * UIScreen.main.scale),
                    resolutionHeight: Int(UIScreen.main.bounds.height * UIScreen.main.scale),
                    screenSizeInches: Self.screenSizeInches(),
                    orientation: "Landscape",
                    os: "tvOS \(UIDevice.current.systemVersion)",
                    device: UIDevice.current.name,
                    brand: "Apple",
                    manufacturer: "Apple Inc.",
                    latitude: 0.0,   // Apple TV has no GPS
                    longitude: 0.0,
                    ramGb: Self.getTotalRAM(),
                    romGb: Self.getAvailableStorage()
                )

                // 🔥 Single call that runs the full flow
                let result = try await DeviceActivationAPI.shared.activateDeviceFullFlow(payload: payload)
                
                // FINAL success response from poll API
                self.activationStatus = result.status
                
            } catch {
                self.errorMessage = error.localizedDescription
            }

            self.isLoading = false
        }
    }
    
    // MARK: - Helper Methods
    
    static func screenSizeInches() -> Int {
        let model = tvModelName()
        switch model {
        case "AppleTV6,2": return 55 // Apple TV 4K 2nd gen example
        case "AppleTV6,1": return 32 // Apple TV 4K 1st gen example
        default: return 55
        }
    }

    static func tvModelName() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = Mirror(reflecting: sysinfo.machine).children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return machine
    }

    static func getTotalRAM() -> Double {
        return Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024 / 1024
    }

    static func getAvailableStorage() -> Double {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let size = attrs[.systemSize] as? NSNumber {
            return size.doubleValue / 1024 / 1024 / 1024
        }
        return 0
    }
}
