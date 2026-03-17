//
//  ActivationViewModel.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 26/11/25.
//

import Foundation
import UIKit

/// Handles initial device activation: requesting activation, polling status,
/// and exposing activation codes / QR URL and user-friendly error messages.
@MainActor
final class ActivationViewModel: ObservableObject {
    @Published var deviceCode = ""
    @Published var activationStatus = ""
    @Published var activationCode = ""
    @Published var qrURL = ""
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isActivated = false  // Dedicated flag for activation complete
    @Published var isActivationFailed = false  // True when poll returns INACTIVE
    @Published var isCodeExpired = false  // Shows refresh button after 15 min
    @Published var timeRemaining: Int = 15 * 60  // 15 minutes in seconds
    
    private var expirationTimer: Timer?
    private var countdownTimer: Timer?
    private let codeExpirationTime: TimeInterval = 15 * 60 // 15 minutes
    
    deinit {
        DispatchQueue.main.async { [weak self] in
            self?.stopTimers()
        }
    }
    
    private func stopTimers() {
        expirationTimer?.invalidate()
        expirationTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
    
    private func startExpirationTimer() {
        stopTimers()
        isCodeExpired = false
        timeRemaining = Int(codeExpirationTime)
        
        // Countdown timer (updates every second)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                }
            }
        }
        
        // Expiration timer (fires after 15 minutes)
        expirationTimer = Timer.scheduledTimer(withTimeInterval: codeExpirationTime, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleCodeExpired()
            }
        }
        
        print("⏱️ Activation code expires in \(Int(codeExpirationTime / 60)) minutes")
    }
    
    private func handleCodeExpired() {
        stopTimers()
        print("⏰ Activation code expired - checking status...")
        Task { @MainActor in
            do {
                let data = try await ActivationPollAPI.shared.pollOnce(deviceCode: deviceCode)
                let status = data.status.uppercased()
                if status == "ACTIVE" || status == "ACTIVATED" {
                    AppRootViewModel.saveActivation(
                        secureKey: data.secureKey,
                        deviceCode: deviceCode,
                        tickerMessage: data.tickerMessage,
                        logoUrl: data.logoUrl
                    )
                    print("📢 Activated on expiry check: \(data.status)")
                    isActivated = true
                } else {
                    // PENDING or INACTIVE: show Activation Failed for 10 seconds, then refresh code
                    isActivationFailed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                        Task { @MainActor in
                            self?.isActivationFailed = false
                            self?.refreshActivationCode()
                        }
                    }
                }
            } catch {
                refreshActivationCode()
            }
        }
    }
    
    /// Refresh the activation code automatically
    private func refreshActivationCode() {
        print("🔄 Auto-refreshing activation code...")
        isCodeExpired = false
        activateDevice()
    }

    func activateDevice() {
        isLoading = true
        errorMessage = nil
        isActivated = false
        isCodeExpired = false

        Task {
            do {
                let payload = buildActivationPayload()
                let activationURL = AppConfig.current.activationBaseURL.appendingPathComponent("v1/dooh/device/activation/request")
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(payload), let json = String(data: data, encoding: .utf8) {
                    print("📤 Activation request: \(activationURL.absoluteString)\n\(json)")
                } else {
                    print("📤 Activation request: \(activationURL.absoluteString)")
                }

                let result = try await ActivationAPI.shared.requestActivation(payload: payload)
                
                handleActivationResponse(result)
                
                // If backend returned INACTIVE, show activation failed
                if checkIfInactive(result.status) {
                    isActivationFailed = true
                    isLoading = false
                    return
                }
                
                // Start 15-minute expiration timer
                startExpirationTimer()
                
                // Check if already activated from initial request
                if checkIfActivated(result.status) {
                    stopTimers()
                    isActivated = true
                    isLoading = false
                    return
                }

                // Start polling separately
                pollActivation()
            } catch {
                let appError = AppError.from(error)
                self.errorMessage = appError.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func pollActivation() {
        Task {
            do {
                let data = try await ActivationPollAPI.shared.pollUntilActivated(deviceCode: deviceCode)
                activationStatus = data.status
                print("📡 Poll returned status: \(data.status)")
                
                // Set activation flag when status is ACTIVE
                if checkIfActivated(data.status) {
                    // Stop expiration timer on successful activation
                    stopTimers()
                    
                    // Save activation to persist across app launches (including ticker/logo)
                    AppRootViewModel.saveActivation(
                        secureKey: data.secureKey,
                        deviceCode: deviceCode,
                        tickerMessage: data.tickerMessage,
                        logoUrl: data.logoUrl
                    )
                    print("📢 Ticker: \(data.tickerMessage ?? "none"), Logo: \(data.logoUrl ?? "none")")
                    isActivated = true
                } else if checkIfInactive(data.status) {
                    isActivationFailed = true
                }
            } catch {
                if let appErr = error as? AppError, case .activationInactive = appErr {
                    isActivationFailed = true
                } else {
                    let appError = AppError.from(error)
                    self.errorMessage = appError.localizedDescription
                }
            }
            self.isLoading = false
        }
    }
    
    private func checkIfActivated(_ status: String) -> Bool {
        let normalized = status.uppercased()
        return normalized == "ACTIVE" || normalized == "ACTIVATED"
    }
    
    private func checkIfInactive(_ status: String) -> Bool {
        return status.uppercased() == "INACTIVE"
    }
    
    /// Clear activation-failed state and request a new activation code (e.g. after "Try again").
    func retryActivation() {
        isActivationFailed = false
        errorMessage = nil
        activateDevice()
    }

    private func buildActivationPayload() -> ActivationRequest {
        let storage = Self.getStorageInfo()
        let totalStorage = storage?.totalGB ?? Self.getAvailableStorage()
        let freeStorage = storage?.freeGB ?? Self.getAvailableStorage()
        let ram = Self.getTotalRAM()
        
        print(String(format: "🧠 RAM total: %.2f GB | 💾 Storage total: %.2f GB, free: %.2f GB", ram, totalStorage, freeStorage))
        
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
            ramGb: ram,
            romGb: totalStorage
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
        let baseURL = AppConfig.current.sparkPortalURL.absoluteString
        return "\(baseURL)/?cb=\(cb)&code=\(activationCode)"
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

    static func getStorageInfo() -> (totalGB: Double, freeGB: Double)? {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let total = attrs[.systemSize] as? NSNumber,
           let free = attrs[.systemFreeSize] as? NSNumber {
            let gb = 1024.0 * 1024.0 * 1024.0
            return (total.doubleValue / gb, free.doubleValue / gb)
        }
        return nil
    }

    static func getAvailableStorage() -> Double {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let size = attrs[.systemSize] as? NSNumber {
            return size.doubleValue / 1024 / 1024 / 1024
        }
        return 0
    }
}
