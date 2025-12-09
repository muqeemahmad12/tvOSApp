//
//  ActivationAPI.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 03/12/25.
//

import Foundation

final class ActivationAPI {
    static let shared = ActivationAPI()
    private init() {}

    func requestActivation(payload: ActivationRequest) async throws -> ActivationData {
        let base = AppConfig.current.activationBaseURL
        let url = base.appendingPathComponent("v1/dooh/device/activation/request")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(payload)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)

            guard let http = resp as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw AppError.invalidResponse
            }

            let decoded = try JSONDecoder().decode(ActivationResponse.self, from: data)

            guard decoded.code == 200, let activation = decoded.data else {
                throw AppError.server(message: decoded.message)
            }
            print("activation: ", activation)
            return activation
        } catch let decodingError as DecodingError {
            print("❌ Activation decoding error: \(decodingError)")
            throw AppError.decoding
        } catch {
            throw AppError.from(error)
        }
    }
}

