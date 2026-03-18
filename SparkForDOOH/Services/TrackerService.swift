//
//  TrackerService.swift
//  SparkForDOOH
//
//  Sends tracker pixel/URL pings provided in ad metadata.
//

import Foundation

final class TrackerService {
    static let shared = TrackerService()
    private init() {}
    
    /// Fire a list of tracker URLs (best-effort, no retries).
    func fire(urls: [String]) {
        Task.detached(priority: .background) {
            await TVRemoteConfigService.waitUntilLaunchConfigNetworkFinished()
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            for urlString in urls {
                let resolved = urlString.replacingOccurrences(of: "{{EVENT_CLIENT_TIME}}", with: "\(nowMs)")
                guard let url = URL(string: resolved) else { continue }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 10
                do {
                    _ = try await URLSession.shared.data(for: request)
                    print("📡 Tracker fired:", resolved)
                } catch {
                    print("⚠️ Tracker failed:", resolved, error.localizedDescription)
                }
            }
        }
    }
}

