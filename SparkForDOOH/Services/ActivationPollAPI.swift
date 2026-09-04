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

    /// When true, poll always shows Activation Failed (INACTIVE) screen regardless of backend status.
    private let showInactiveScreenOnly = false

    func pollOnce(deviceCode: String) async throws -> ActivationPollData {
        await TVRemoteConfigService.waitUntilLaunchConfigNetworkFinished()
        let url = TVRemoteConfigStore.shared.activationURL(pathComponents: "dooh", "device", "activation", "poll")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["deviceCode": deviceCode]
        req.httpBody = try JSONEncoder().encode(body)
        if let bodyString = String(data: req.httpBody ?? Data(), encoding: .utf8) {
            print("📤 Poll API request: \(url.absoluteString) body: \(bodyString)")
        } else {
            print("📤 Poll API request: \(url.absoluteString)")
        }

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
        NetworkMonitor.shared.markOnline(reason: "ActivationPollSuccess")
        // Always keep the latest secureKey from poll (PENDING or ACTIVE).
        await AppRootViewModel.updateSecureKey(pollData.secureKey)
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

            if showInactiveScreenOnly {
                throw AppError.activationInactive
            }
            if status == "ACTIVE" || status == "ACTIVATED" {
                return result
            }
            if status == "INACTIVE" {
                throw AppError.activationInactive
            }
            } catch {
                if let appErr = error as? AppError, case .activationInactive = appErr {
                    throw appErr
                }
                print("⚠️ Polling attempt \(attempt) failed: \(error)")
            }

            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
        }

        throw AppError.activationTimeout
    }
}

