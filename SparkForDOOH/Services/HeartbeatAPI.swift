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
    }
    
    /// Heartbeat interval in seconds (60 seconds as per spec)
    private let heartbeatInterval: TimeInterval = 60
    
    /// Timer for periodic heartbeat
    private var heartbeatTimer: Timer?
    
    /// Current playback info for heartbeat payload
    private var currentSequenceIndex: Int = 0
    private var currentAdId: String = ""
    private var isPlaying: Bool = false
    private var lastSyncTime: Date?
    private var lastPlayedTime: Date?
    
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
        self.lastPlayedTime = Date()
    }
    
    /// Update last sync time (called after successful playlist sync)
    func updateLastSyncTime() {
        self.lastSyncTime = Date()
    }
    
    /// Get current network status
    private func getNetworkStatus() -> String {
        // Simple network check - in production, could use NWPathMonitor
        let url = URL(string: "https://www.apple.com")!
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        
        // For now, return "connected" as we're already making API calls
        // A more robust check would use NWPathMonitor
        return "connected"
    }
    
    // MARK: - Private Methods
    
    /// Send a single heartbeat to the backend
    private func sendHeartbeat() async {
        let baseURL = AppConfig.current.activationBaseURL
        let url = baseURL.appendingPathComponent("v1/dooh/device/heartbeat")
        
        let deviceId = await UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let secureKey = await AppRootViewModel.getSavedSecureKey() ?? ""
        let deviceCode = await AppRootViewModel.getSavedDeviceCode() ?? ""
        
        // Format timestamps
        let isoFormatter = ISO8601DateFormatter()
        let lastSyncString = lastSyncTime.map { isoFormatter.string(from: $0) } ?? ""
        let lastPlayedString = lastPlayedTime.map { isoFormatter.string(from: $0) } ?? ""
        
        let payload: [String: Any] = await [
            // Required fields per spec
            "screen_id": AppConfig.current.screenId,
            "device_id": deviceId,
            "last_sync": lastSyncString,
            "last_played": lastPlayedString,
            "network_status": getNetworkStatus(),
            // Additional context fields
            "deviceCode": deviceCode,
            "secureKey": secureKey,
            "timestamp": isoFormatter.string(from: Date()),
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
            request.setValue(AppConfig.current.apiKey, forHTTPHeaderField: "x-api-key")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.timeoutInterval = 30
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("⚠️ Heartbeat: Invalid response")
                return
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                // Parse and log response
                if let heartbeatResponse = try? JSONDecoder().decode(HeartbeatResponse.self, from: data) {
                    print("💓 Heartbeat: \(heartbeatResponse.message ?? "OK")")
                } else {
                    print("💓 Heartbeat sent successfully")
                }
            } else {
                print("⚠️ Heartbeat failed: HTTP \(httpResponse.statusCode)")
            }
        } catch {
            print("❌ Heartbeat error: \(error.localizedDescription)")
        }
    }
}

