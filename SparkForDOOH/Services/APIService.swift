//
//  APIService.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import Foundation

/// Simple shared API client for playlist / item sequence info.
final class APIService {
    static let shared = APIService()
    private init() {}

    /// Fetch the ad item sequence info for a given screen.
    func fetchItemSeqInfo(screenId: String, reqNum: Int) async throws -> ItemSeqInfoResponse {
        let base = AppConfig.current.drsBaseURL
        let url = base.appendingPathComponent("drs/v2/quest")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = ["screenid": screenId, "reqNum": reqNum]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        do {
            let decoded = try JSONDecoder().decode(ItemSeqInfoResponse.self, from: data)
            let groups = decoded.groupedAds
            print("✅ API Success — Total Groups: \(groups.count)")
            for group in groups {
                print("▶️ Sequence \(group.sequence): \(group.ii.count) ads")
                for ad in group.ii {
                    print("   🔹 \(ad.itemid): \(ad.assettype) — \(ad.itemurl)")
                }
            }
            return decoded
        } catch {
            print("❌ Decoding error: \(error)")
            if let raw = String(data: data, encoding: .utf8) {
                print("Raw JSON:\n\(raw)")
            }
            throw error
        }
    }
}

