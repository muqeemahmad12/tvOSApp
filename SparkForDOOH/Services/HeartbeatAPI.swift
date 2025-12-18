//
//  HeartbeatAPI.swift
//  SparkForDOOH
//
//  Sends periodic heartbeat signals to the backend for device health monitoring.
//

import Foundation
import UIKit

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when ticker/logo is updated from heartbeat response
    static let tickerUpdated = Notification.Name("com.doceree.sparkfordooh.tickerUpdated")
}

/// Heartbeat API for sending device status to the backend.
/// This enables remote monitoring and can receive updated configuration (ticker, logo).
final class HeartbeatAPI {
    static let shared = HeartbeatAPI()
    private init() {}
    
    /// Heartbeat response model
    struct HeartbeatResponse: Codable {
        let timestamp: String?
        let code: Int?
        let status: String?
        let message: String?
        let data: HeartbeatData?
    }
    
    struct HeartbeatData: Codable {
        let tickerMessage: String?
        let logoUrl: String?
        let config: HeartbeatConfig?
    }
    
    struct HeartbeatConfig: Codable {
        let playlistRefreshInterval: Int?
        let heartbeatInterval: Int?
    }
    
    /// Heartbeat interval in seconds (default 5 minutes)
    private let heartbeatInterval: TimeInterval = 5 * 60
    
    /// Timer for periodic heartbeat
    private var heartbeatTimer: Timer?
    
    /// Current playback info for heartbeat payload
    private var currentSequenceIndex: Int = 0
    private var currentAdId: String = ""
    private var isPlaying: Bool = false
    
    // MARK: - Public Methods
    
    /// Start the heartbeat timer
    func startHeartbeat() {
        guard heartbeatTimer == nil else { return }
        
        print("💓 Starting heartbeat service (interval: \(Int(heartbeatInterval))s)")
        
        // Send initial heartbeat
        Task {
            await sendHeartbeat()
        }
        
        // Schedule periodic heartbeats
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.sendHeartbeat()
            }
        }
    }
    
    /// Stop the heartbeat timer
    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        print("💔 Heartbeat service stopped")
    }
    
    /// Update current playback status (called by AdPlayerViewModel)
    func updatePlaybackStatus(sequenceIndex: Int, adId: String, isPlaying: Bool) {
        self.currentSequenceIndex = sequenceIndex
        self.currentAdId = adId
        self.isPlaying = isPlaying
    }
    
    // MARK: - Private Methods
    
    /// Send a single heartbeat to the backend
    private func sendHeartbeat() async {
        let baseURL = AppConfig.current.activationBaseURL
        let url = baseURL.appendingPathComponent("api/v1/dooh/heartbeat")
        
        let deviceId = await UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let secureKey = await AppRootViewModel.getSavedSecureKey() ?? ""
        let deviceCode = await AppRootViewModel.getSavedDeviceCode() ?? ""
        
        let payload: [String: Any] = await [
            "deviceId": deviceId,
            "deviceCode": deviceCode,
            "secureKey": secureKey,
            "screenId": AppConfig.current.screenId,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "status": isPlaying ? "playing" : "idle",
            "currentSequence": currentSequenceIndex,
            "currentAdId": currentAdId,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "osVersion": UIDevice.current.systemVersion,
            "environment": AppConfig.current.environment
        ]
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.timeoutInterval = 30
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("⚠️ Heartbeat: Invalid response")
                return
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                print("💓 Heartbeat sent successfully")
                
                // Parse response for updated configuration
                if let heartbeatResponse = try? JSONDecoder().decode(HeartbeatResponse.self, from: data),
                   let heartbeatData = heartbeatResponse.data {
                    
                    var didUpdate = false
                    
                    // Update ticker message if changed
                    if let tickerMessage = heartbeatData.tickerMessage {
                        await AppRootViewModel.updateTickerMessage(tickerMessage)
                        print("📢 Updated ticker message: \(tickerMessage)")
                        didUpdate = true
                    }
                    
                    // Update logo URL if changed
                    if let logoUrl = heartbeatData.logoUrl {
                        await AppRootViewModel.updateLogoUrl(logoUrl)
                        print("🖼️ Updated logo URL: \(logoUrl)")
                        didUpdate = true
                    }
                    
                    // Notify UI to refresh ticker/logo
                    if didUpdate {
                        await MainActor.run {
                            NotificationCenter.default.post(name: .tickerUpdated, object: nil)
                        }
                    }
                }
            } else {
                print("⚠️ Heartbeat failed: HTTP \(httpResponse.statusCode)")
            }
        } catch {
            print("❌ Heartbeat error: \(error.localizedDescription)")
        }
    }
}

