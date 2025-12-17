//
//  ImpressionTrackingAPI.swift
//  SparkForDOOH
//
//  Reports ad impressions and completions to the backend for monetization tracking.
//

import Foundation

/// Tracks ad impressions and completions for monetization.
final class ImpressionTrackingAPI {
    static let shared = ImpressionTrackingAPI()
    private init() {}
    
    /// Report when an ad starts playing (impression).
    func trackImpression(ad: AdItemModel, screenId: String) {
        Task {
            await sendEvent(type: "impression", ad: ad, screenId: screenId)
        }
    }
    
    /// Report when a video ad finishes playing (completion).
    func trackCompletion(ad: AdItemModel, screenId: String) {
        Task {
            await sendEvent(type: "completion", ad: ad, screenId: screenId)
        }
    }
    
    /// Report when an image ad finishes displaying (view complete).
    func trackViewComplete(ad: AdItemModel, screenId: String, durationSeconds: Int) {
        Task {
            await sendEvent(type: "view_complete", ad: ad, screenId: screenId, duration: durationSeconds)
        }
    }
    
    // MARK: - Private
    
    private func sendEvent(type: String, ad: AdItemModel, screenId: String, duration: Int? = nil) async {
        let base = AppConfig.current.drsBaseURL
        let url = base.appendingPathComponent("v1/dooh/impression/track")
        
        var payload: [String: Any] = await [
            "eventType": type,
            "screenId": screenId,
            "itemId": ad.itemid,
            "itemUrl": ad.itemurl,
            "assetType": ad.assettype,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "deviceId": AppRootViewModel.getSavedDeviceCode() ?? "unknown"
        ]
        
        if let duration = duration {
            payload["durationSeconds"] = duration
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                print("📊 Tracked \(type): \(ad.itemid)")
            } else {
                print("⚠️ Impression tracking failed: non-2xx response")
            }
        } catch {
            // Don't fail silently but also don't block playback
            print("⚠️ Impression tracking error: \(error.localizedDescription)")
        }
    }
}

