//
//  ActivationRequest.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 26/11/25.
//

import Foundation

struct ActivationRequest: Codable {
    let deviceId: String
    let resolutionWidth: Int
    let resolutionHeight: Int
    let screenSizeInches: Int
    let orientation: String
    let os: String
    let device: String
    let brand: String
    let manufacturer: String
    let latitude: Double
    let longitude: Double
    let ramGb: Double
    let romGb: Double
}

struct ActivationResponse: Codable {
    let timestamp: String
    let code: Int
    let status: String
    let message: String
    let data: ActivationData?
}

struct ActivationData: Codable {
    let deviceCode: String
    let userCode: String
    let status: String
    let expiresAt: String
}
