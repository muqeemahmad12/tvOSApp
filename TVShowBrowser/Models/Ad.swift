//
//  Ad.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import Foundation

// MARK: - Ad Model
struct Ad: Identifiable, Codable {
    enum AdType: String, Codable {
        case image, video, gif, html
    }

    let id: UUID = UUID()
    let type: AdType
    let url: URL
    let duration: TimeInterval

    var uiAdType: UIAdType {
        switch type {
        case .image, .gif, .html:
            // convert HTML/GIF to an image/video representation as needed
            return .image(url: url.absoluteString)
        case .video:
            return .video(url: url.absoluteString)
        }
    }
}
