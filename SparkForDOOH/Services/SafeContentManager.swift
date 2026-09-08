//
//  SafeContentManager.swift
//  SparkForDOOH
//
//  Last-resort image helper when an ad image cannot be resolved from cache/bundle.
//

import Foundation
import UIKit

final class SafeContentManager {
    static let shared = SafeContentManager()

    private init() {}

    /// Placeholder image used only when a creative image fails to resolve.
    func getSafeContentImage() -> UIImage? {
        UIImage(named: "placeholder_image")
    }
}
