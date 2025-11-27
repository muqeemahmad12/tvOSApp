//
//  ActivationPollModel.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 26/11/25.
//

import Foundation

struct ActivationPollResponse: Codable {
    let timestamp: String
    let code: Int
    let status: String
    let message: String
    let data: ActivationPollData?
}

struct ActivationPollData: Codable {
    let status: String
    let secureKey: String?
    let logoUrl: String?
    let tickerMessage: String?
}
