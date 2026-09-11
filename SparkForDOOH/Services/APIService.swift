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

            if !(200...299).contains(http.statusCode) {
                print("❌ API Error - Status: \(http.statusCode)")
                print("📥 Body: \(raw.isEmpty ? "<empty>" : raw)")
                throw AppError.invalidResponse
            }

            guard !data.isEmpty else {
                print("❌ Quest returned empty body (HTTP \(http.statusCode))")
                throw AppError.invalidResponse
            }

            do {
                let decoded = try JSONDecoder().decode(ItemSeqInfoResponse.self, from: data)
                let groups = decoded.groupedAds
                let playable = groups.displayableGroups()
                NetworkMonitor.shared.markOnline(reason: "QuestSuccess")

                if let pretty = Self.prettyJSON(from: data) {
                    print("📥 Quest response JSON:\n\(pretty)")
                }

                print("✅ Quest decoded — screenid=\(decoded.screenid ?? "nil") status=\(decoded.status ?? "nil")")
                print("   Active groups: \(groups.count) | Playable groups: \(playable.count)")
                Self.logGroups("RAW (active)", groups)
                Self.logGroups("PLAYABLE (after filter)", playable)

                return decoded
            } catch {
                print("❌ Decoding error: \(error)")
                if let pretty = Self.prettyJSON(from: data) {
                    print("Raw JSON:\n\(pretty)")
                } else {
                    print("Raw JSON:\n\(raw)")
                }
                throw AppError.decoding
            }
        } catch {
            throw AppError.from(error)
        }
    }

    private static func prettyJSON(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        return text
    }

    private static func logGroups(_ label: String, _ groups: [AdSequenceGroup]) {
        print("📋 \(label): \(groups.count) group(s)")
        guard !groups.isEmpty else {
            print("   (none)")
            return
        }
        for group in groups {
            print("▶️ Sequence \(group.sequence) facility=\(group.facilityid.isEmpty ? "nil" : group.facilityid) active=\(group.is_active) — \(group.ii.count) item(s)")
            for (idx, ad) in group.ii.enumerated() {
                let id = ad.itemid.isEmpty ? "null" : ad.itemid
                let dur = ad.duration.map(String.init) ?? "null"
                let flex = ad.isFlex.map { $0 ? "true" : "false" } ?? "null"
                let playable = ad.hasMinimumPlayableFields ? "yes" : "no"
                print("   [\(idx)] id=\(id) type=\(ad.assettype) duration=\(dur) is_flex=\(flex) playable=\(playable)")
                print("        url=\(ad.itemurl.isEmpty ? "null" : ad.itemurl)")
            }
        }
    }
}


