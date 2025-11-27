//
//  DeviceActivationAPI.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 26/11/25.
//

import Foundation

final class DeviceActivationAPI {
    
    static let shared = DeviceActivationAPI()
    private init() {}

    private let baseURL = "https://dev-keen.doceree.com"
    
    // MARK: - PUBLIC: Single Flow Call
    func activateDeviceFullFlow(payload: ActivationRequest) async throws -> ActivationPollData {
        // Step 1 → Request activation
        let activation = try await requestDeviceActivation(payload: payload)
        
        // Step 2 → Poll until activated
        let finalStatus = try await pollUntilActivated(deviceCode: activation.deviceCode)
        
        return finalStatus
    }
    
    // MARK: - Step 1: Request Activation
    private func requestDeviceActivation(payload: ActivationRequest) async throws -> ActivationData {
        
        guard let url = URL(string: "\(baseURL)/v1/dooh/device/activation/request") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            print("Status:", httpResponse.statusCode)
            print("Response body:", String(data: data, encoding: .utf8) ?? "N/A")
            throw NSError(domain: "HTTPError", code: httpResponse.statusCode)
        }
        
        let decoded = try JSONDecoder().decode(ActivationResponse.self, from: data)
        
        guard decoded.code == 200, let activationData = decoded.data else {
            throw NSError(domain: "APIError", code: decoded.code, userInfo: [
                NSLocalizedDescriptionKey: decoded.message
            ])
        }

        return activationData
    }

    // MARK: - Step 2: Poll Continuously
    private func pollUntilActivated(deviceCode: String) async throws -> ActivationPollData {
        while true {
            let result = try await pollActivation(deviceCode: deviceCode)
            
            if result.status.uppercased() == "ACTIVATED" {
                return result // final result
            }
            
            try? await Task.sleep(nanoseconds: 5_000_000_000) // wait 5 seconds
        }
    }
    
    // MARK: - Poll API
    private func pollActivation(deviceCode: String) async throws -> ActivationPollData {
        guard let url = URL(string: "\(baseURL)/v1/dooh/device/activation/poll") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONEncoder().encode(["deviceCode": deviceCode])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(ActivationPollResponse.self, from: data)

        guard decoded.code == 200, let pollData = decoded.data else {
            throw NSError(domain: "APIError", code: decoded.code, userInfo: [
                NSLocalizedDescriptionKey: decoded.message
            ])
        }

        return pollData
    }
}
