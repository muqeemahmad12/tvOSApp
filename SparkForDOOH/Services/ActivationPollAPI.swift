//
//  ActivationPollAPI.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 03/12/25.
//

import Foundation

/// Service that polls the backend for activation status of a device, with
/// a small retry/backoff loop for resilience.
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

        do {
        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
                throw AppError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(ActivationPollResponse.self, from: data)

        guard decoded.code == 200, let pollData = decoded.data else {
                throw AppError.server(message: decoded.message)
        }
        
        print("pollData: ", pollData)
        return pollData
        } catch let decodingError as DecodingError {
            print("❌ Activation poll decoding error: \(decodingError)")
            throw AppError.decoding
        } catch {
            throw AppError.from(error)
        }
    }

    /// Continuous polling with simple retry/backoff until activated or timeout.
    func pollUntilActivated(
        deviceCode: String,
        maxAttempts: Int = 20,
        delaySeconds: UInt64 = 15
    ) async throws -> ActivationPollData {
        var attempt = 0

        while attempt < maxAttempts {
            attempt += 1

            do {
            let result = try await pollOnce(deviceCode: deviceCode)
            let status = result.status.uppercased()
            
            if status == "ACTIVE" || status == "ACTIVATED" {
                return result
            }
            } catch {
                // For polling we treat transient failures as retryable and keep trying
                print("⚠️ Polling attempt \(attempt) failed: \(error)")
            }

            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
        }

        throw AppError.activationTimeout
    }
}

