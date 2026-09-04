//
//  APIService.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import Foundation
import UIKit

/// Simple shared API client for playlist / item sequence info from the DRS backend.
/// Responsible for making the network call and decoding into `ItemSeqInfoResponse`.
final class APIService {
    static let shared = APIService()
    private init() {}

    /// Fetch the ad item sequence info for a given screen.
    func fetchItemSeqInfo(screenId: String, reqNum: Int) async throws -> ItemSeqInfoResponse {
        await TVRemoteConfigService.waitUntilLaunchConfigNetworkFinished()
        let url = TVRemoteConfigStore.shared.drsQuestURL()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // quest: x-api-key = secureKey from activation poll; x-dev-id = device code.
        let secureKey = await AppRootViewModel.getSavedSecureKey() ?? ""
        request.setValue(secureKey, forHTTPHeaderField: "x-api-key")
        let deviceCode = await AppRootViewModel.getSavedDeviceCode() ?? ""
        request.setValue(deviceCode, forHTTPHeaderField: "x-dev-id")

        let payload: [String: Any] = [
            "reqNum": reqNum
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let bodyString = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        print("📤 Quest request")
        print("   \(request.httpMethod ?? "POST") \(url.absoluteString)")
        print("   Headers:")
        print("     Content-Type: \(request.value(forHTTPHeaderField: "Content-Type") ?? "")")
        print("     x-api-key (secureKey): \(secureKey)")
        print("     x-dev-id: \(deviceCode)")
        print("   Body: \(bodyString)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw AppError.invalidResponse
            }

            let raw = String(data: data, encoding: .utf8) ?? ""
            print("📥 Quest response HTTP \(http.statusCode), \(data.count) bytes")
            print("📥 Raw quest response: \(raw.isEmpty ? "<empty>" : raw)")

            if !(200...299).contains(http.statusCode) {
                print("❌ API Error - Status: \(http.statusCode)")
                throw AppError.invalidResponse
            }

            guard !data.isEmpty else {
                print("❌ Quest returned empty body (HTTP \(http.statusCode))")
                throw AppError.invalidResponse
            }

            do {
                let decoded = try JSONDecoder().decode(ItemSeqInfoResponse.self, from: data)
                let groups = decoded.groupedAds
                NetworkMonitor.shared.markOnline(reason: "QuestSuccess")
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
                print("Raw JSON:\n\(raw)")
                throw AppError.decoding
            }
        } catch {
            throw AppError.from(error)
        }
    }
}


