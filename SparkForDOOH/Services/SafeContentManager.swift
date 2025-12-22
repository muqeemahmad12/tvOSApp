//
//  SafeContentManager.swift
//  SparkForDOOH
//
//  Manages fallback/safe content for when playlist is empty or unavailable.
//

import Foundation
import UIKit

/// Provides safe/default content when the main playlist is empty or unavailable.
/// This ensures the screen always has something appropriate to display.
final class SafeContentManager {
    static let shared = SafeContentManager()
    
    // MARK: - Safe Content Configuration
    
    /// Bundle resource names for safe content (should be added to app bundle)
    private let safeImageName = "safe_content_placeholder"
    private let safeVideoName = "safe_content_video"
    
    /// Creates a fallback ad group using bundled safe content
    func getSafeContentGroup() -> AdSequenceGroup? {
        // Try to use bundled placeholder image first
        if let _ = UIImage(named: safeImageName) {
            print("🛡️ Using bundled safe content image: \(safeImageName)")
            
            var safeAd = AdItemModel(
                itemid: "safe_content_001",
                assettype: "image",
                assetcat: nil,
                itemurl: "bundle://\(safeImageName)",
                itemsize: nil,
                isFlex: nil,
                trackerlist: nil,
                itemspeciality: nil,
                subcampaignid: nil,
                schedulestarttime: nil,
                scheduleendtime: nil
            )
            safeAd.sequence = 1
            safeAd.facilityid = "safe_content"
            
            return AdSequenceGroup(
                facilityid: "safe_content",
                sequence: 1,
                ii: [safeAd],
                is_active: true
            )
        }
        
        // Fallback: create a simple placeholder group
        print("⚠️ No bundled safe content found - using generic placeholder")
        return nil
    }
    
    /// Check if we have safe content available in the bundle
    var hasSafeContent: Bool {
        UIImage(named: safeImageName) != nil ||
        Bundle.main.url(forResource: safeVideoName, withExtension: "mp4") != nil
    }
    
    /// Get the safe content image (for display in view)
    func getSafeContentImage() -> UIImage? {
        // First try the designated safe content image
        if let image = UIImage(named: safeImageName) {
            return image
        }
        
        // Fallback to placeholder_image (which exists in the app)
        if let image = UIImage(named: "placeholder_image") {
            return image
        }
        
        return nil
    }
}

