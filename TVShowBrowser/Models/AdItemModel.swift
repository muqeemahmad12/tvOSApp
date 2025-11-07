//
//  AdItemModel.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import Foundation

// MARK: - Root Response
struct ItemSeqInfoResponse: Codable {
    let screenid: String
    let status: String
    let item1: [AdSequenceGroup]
}

// MARK: - Sequence group — can contain 1–3 ads
struct AdSequenceGroup: Codable, Identifiable, Equatable {
    var id: Int { sequence }
    let facilityid: String
    let sequence: Int
    let ii: [AdItemModel]
    let is_active: Bool
    
    static func == (lhs: AdSequenceGroup, rhs: AdSequenceGroup) -> Bool {
        lhs.sequence == rhs.sequence
    }
}

// MARK: - Ad Item
struct AdItemModel: Codable, Identifiable, Equatable {
    var id: String { itemid }

    let itemid: String
    let assettype: String
    let assetcat: String?
    let itemurl: String
    let itemsize: String?
    let isFlex: Bool?
    let trackerlist: [String]?
    let itemspeciality: String?
    let subcampaignid: String?
    let schedulestarttime: String?
    let scheduleendtime: String?

    // Enriched metadata (not part of JSON, set after mapping)
    var sequence: Int?
    var facilityid: String?

    enum CodingKeys: String, CodingKey {
        case itemid, assettype, assetcat, itemurl, itemsize
        case isFlex = "is_flex"
        case trackerlist, itemspeciality, subcampaignid, schedulestarttime, scheduleendtime
    }

    static func == (lhs: AdItemModel, rhs: AdItemModel) -> Bool {
        lhs.itemid == rhs.itemid && lhs.itemurl == rhs.itemurl
    }
}

// MARK: - Convenience Helpers (non-flattening)
extension ItemSeqInfoResponse {
    /// Each entry is a sequence group (preserves 1..N ads per screen)
    var groupedAds: [AdSequenceGroup] {
        item1
            .filter { $0.is_active }
            .sorted { $0.sequence < $1.sequence }
    }
}

// size helper
extension AdItemModel {
    var isTooLarge: Bool {
        guard let size = itemsize else { return false }
        let components = size.lowercased().split(separator: "x")
        guard components.count == 2,
              let width = Int(components[0]),
              let height = Int(components[1]) else {
            return false
        }
        return width > 2126 || height > 3840
    }
}
