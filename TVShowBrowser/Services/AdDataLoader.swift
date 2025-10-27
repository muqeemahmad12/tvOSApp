//
//  AdDataLoader.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import Foundation

final class AdDataLoader {
    static func loadConfig() -> AdConfig? {
        guard let url = Bundle.main.url(forResource: "ads", withExtension: "json") else {
            print("❌ ads.json not found in bundle")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(AdConfig.self, from: data)
            return config
        } catch {
            print("❌ Failed to decode ads.json: \(error)")
            return nil
        }
    }
}

