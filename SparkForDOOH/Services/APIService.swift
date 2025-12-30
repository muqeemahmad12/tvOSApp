//
//  APIService.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import Foundation

/// Simple shared API client for playlist / item sequence info from the DRS backend.
/// Responsible for making the network call and decoding into `ItemSeqInfoResponse`.
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
        request.setValue("fdd74745-a0ed-440c-ad10-3815d659a599", forHTTPHeaderField: "x-api-key")
        
        // Get the secureKey from activation (required by API - sent in header)
        let secureKey = await AppRootViewModel.getSavedSecureKey() ?? ""
        request.setValue(secureKey, forHTTPHeaderField: "X-Requested-With")

        // Only reqNum in body - screenId is derived from securityKey on server
        let payload: [String: Any] = [
            "reqNum": reqNum
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        do {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Log request details for debugging
        print("📤 API Request: \(url)")
        print("📤 Payload: reqNum=\(reqNum)")
        print("📤 Header X-Requested-With: \(secureKey) (length: \(secureKey.count))")

        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        
        // Log response even if not 2xx
        if !(200...299).contains(http.statusCode) {
            print("❌ API Error - Status: \(http.statusCode)")
            if let raw = String(data: data, encoding: .utf8) {
                print("❌ Response Body:\n\(raw)")
            }
            throw AppError.invalidResponse
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
                throw AppError.decoding
            }
        } catch {
            throw AppError.from(error)
        }
    }
}


