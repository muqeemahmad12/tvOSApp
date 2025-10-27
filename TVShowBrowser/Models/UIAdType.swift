//
//  AdType.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 09/10/25.
//

import Foundation

enum UIAdType: Identifiable, Equatable {
    var id: String { UUID().uuidString }

    case image(url: String)
    case video(url: String)
    case lottie(name: String)
    case vast(url: String)

    static func == (lhs: UIAdType, rhs: UIAdType) -> Bool {
        switch (lhs, rhs) {
        case (.image(let a), .image(let b)),
             (.video(let a), .video(let b)),
             (.lottie(let a), .lottie(let b)),
             (.vast(let a), .vast(let b)):
            return a == b
        default:
            return false
        }
    }
}
