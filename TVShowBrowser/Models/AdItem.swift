//
//  AdItem.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import Foundation

struct AdItem: Hashable, Identifiable, Codable {
    let id = UUID()
    let type: String
    let url: String?
    let name: String?
    let duration: TimeInterval?

    var adType: UIAdType {
        switch type.lowercased() {
        case "image": return .image(url: url ?? "")
        case "video": return .video(url: url ?? "")
        case "lottie": return .lottie(name: name ?? "")
        case "vast": return .vast(url: url ?? "")
        default: return .image(url: "")
        }
    }

    var slideDuration: TimeInterval {
        duration ?? 5 // default slide duration
    }
}
