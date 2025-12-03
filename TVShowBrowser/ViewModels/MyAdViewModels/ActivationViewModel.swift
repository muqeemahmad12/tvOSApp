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
    @Published var deviceCode = ""
    @Published var activationStatus = ""
    @Published var activationCode = ""
    @Published var qrURL = ""
    @Published var errorMessage: String?
    @Published var isLoading = false

    func activateDevice() {
        isLoading = true

        Task {
            do {
                let payload = buildActivationPayload()

                let result = try await ActivationAPI.shared.requestActivation(payload: payload)
                
                handleActivationResponse(result)

                // polling separately
                pollActivation()
            } catch {
                self.errorMessage = error.localizedDescription
            }

            self.isLoading = false
        }
    }
    
    func pollActivation() {
        Task {
            do {
                let data = try await ActivationPollAPI.shared.pollUntilActivated(deviceCode: deviceCode)
                activationStatus = data.status
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func buildActivationPayload() -> ActivationRequest {
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
        return payload
    }
    
    private func handleActivationResponse(_ data: ActivationData) {
        self.deviceCode = data.deviceCode
        self.activationStatus = data.status
        self.activationCode = data.userCode      // assuming userCode IS the activation code

        self.qrURL = generateQRUrl()
    }

    func generateQRUrl() -> String {
        guard !activationCode.isEmpty else { return "" }
        let cb = generateCB()
        return "https://spark.doceree.com/?cb=\(cb)&code=\(activationCode)"
    }
    
    func generateCB() -> String {

        // 1. Current epoch time in nanoseconds
        let nanos = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)

        // 2. Random 4-byte salt
        var saltBytes = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)

        // Convert salt to hex string
        let saltHex = saltBytes.map { String(format: "%02X", $0) }.joined()

        // 3. Combine timestamp + salt
        return "\(nanos)\(saltHex)"
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
