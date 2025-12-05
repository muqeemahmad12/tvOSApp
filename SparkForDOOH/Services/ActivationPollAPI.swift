//
//  ActivationPollAPI.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 03/12/25.
//

import Foundation

final class ActivationPollAPI {
    static let shared = ActivationPollAPI()
    private init() {}

    func pollOnce(deviceCode: String) async throws -> ActivationPollData {
        let base = AppConfig.current.activationBaseURL
        let url = base.appendingPathComponent("v1/dooh/device/activation/poll")

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

