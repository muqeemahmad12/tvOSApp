//
//  AdItemModel.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import Foundation

// MARK: - Root Response
struct ItemSeqInfoResponse: Codable {
    let screenid: String?
    let status: String?
    let item1: [AdSequenceGroup]
    
    enum CodingKeys: String, CodingKey {
        case screenid, status, item1
    }
    
    init(screenid: String?, status: String?, item1: [AdSequenceGroup]) {
        self.screenid = screenid
        self.status = status
        self.item1 = item1
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        screenid = try container.decodeIfPresent(String.self, forKey: .screenid)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        // Default to empty array if item1 key is missing to avoid keyNotFound crashes
        item1 = try container.decodeIfPresent([AdSequenceGroup].self, forKey: .item1) ?? []
    }
}

// MARK: - Sequence group — can contain 1–3 ads
struct AdSequenceGroup: Codable, Identifiable, Equatable {
    var id: Int { sequence }
    let facilityid: String
    let sequence: Int
    var ii: [AdItemModel]
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
    /// Display seconds for image creatives (from quest JSON). Nil → player default.
    let duration: Int?
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
        case itemid, assettype, assetcat, itemurl, itemsize, duration
        case isFlex = "is_flex"
        case trackerlist, itemspeciality, subcampaignid, schedulestarttime, scheduleendtime
    }

    init(
        itemid: String,
        assettype: String,
        assetcat: String? = nil,
        itemurl: String,
        itemsize: String? = nil,
        duration: Int? = nil,
        isFlex: Bool? = nil,
        trackerlist: [String]? = nil,
        itemspeciality: String? = nil,
        subcampaignid: String? = nil,
        schedulestarttime: String? = nil,
        scheduleendtime: String? = nil,
        sequence: Int? = nil,
        facilityid: String? = nil
    ) {
        self.itemid = itemid
        self.assettype = assettype
        self.assetcat = assetcat
        self.itemurl = itemurl
        self.itemsize = itemsize
        self.duration = duration
        self.isFlex = isFlex
        self.trackerlist = trackerlist
        self.itemspeciality = itemspeciality
        self.subcampaignid = subcampaignid
        self.schedulestarttime = schedulestarttime
        self.scheduleendtime = scheduleendtime
        self.sequence = sequence
        self.facilityid = facilityid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // API sometimes sends null itemid/itemurl — treat as empty and drop later.
        itemid = try container.decodeIfPresent(String.self, forKey: .itemid) ?? ""
        assettype = try container.decode(String.self, forKey: .assettype)
        assetcat = try container.decodeIfPresent(String.self, forKey: .assetcat)
        itemurl = try container.decodeIfPresent(String.self, forKey: .itemurl) ?? ""
        itemsize = try container.decodeIfPresent(String.self, forKey: .itemsize)
        if let i = try? container.decode(Int.self, forKey: .duration) {
            duration = i
        } else if let s = try? container.decode(String.self, forKey: .duration), let i = Int(s) {
            duration = i
        } else {
            duration = nil
        }
        isFlex = try container.decodeIfPresent(Bool.self, forKey: .isFlex)
        trackerlist = try container.decodeIfPresent([String].self, forKey: .trackerlist)
        itemspeciality = try container.decodeIfPresent(String.self, forKey: .itemspeciality)
        subcampaignid = try container.decodeIfPresent(String.self, forKey: .subcampaignid)
        schedulestarttime = try container.decodeIfPresent(String.self, forKey: .schedulestarttime)
        scheduleendtime = try container.decodeIfPresent(String.self, forKey: .scheduleendtime)
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
    /// Only `image` and `video` are shown on the player (e.g. `Banner` is not displayable).
    var isDisplayableAsset: Bool {
        let type = assettype.lowercased()
        return type == "image" || type == "video"
    }

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

extension Array where Element == AdSequenceGroup {
    /// Groups containing at least one image/video creative (Banner-only groups dropped).
    func displayableGroups() -> [AdSequenceGroup] {
        compactMap { group in
            let kept = group.ii.filter {
                $0.isDisplayableAsset && !$0.itemid.isEmpty && !$0.itemurl.isEmpty
            }
            guard !kept.isEmpty else { return nil }
            var copy = group
            copy.ii = kept
            return copy
        }
    }
}
