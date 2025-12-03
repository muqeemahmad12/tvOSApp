//
//  ActivationPollAPI.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 03/12/25.
//

import Foundation

final class ActivationPollAPI {
    static let shared = ActivationPollAPI()
    private init() {}

    private let baseURL = "https://dev-keen.doceree.com"

    func pollOnce(deviceCode: String) async throws -> ActivationPollData {
        guard let url = URL(string: "\(baseURL)/v1/dooh/device/activation/poll") else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["deviceCode": deviceCode])

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(ActivationPollResponse.self, from: data)

        guard decoded.code == 200, let pollData = decoded.data else {
            throw NSError(domain: "APIError", code: decoded.code, userInfo: [
                NSLocalizedDescriptionKey: decoded.message
            ])
        }
        
        print("pollData: ", pollData)
        return pollData
    }

    /// Optional: continuous polling
    func pollUntilActivated(deviceCode: String) async throws -> ActivationPollData {
        while true {
            let result = try await pollOnce(deviceCode: deviceCode)

            if result.status.uppercased() == "ACTIVATED" {
                return result
            }

            try? await Task.sleep(nanoseconds: 15_000_000_000)
        }
    }
}

