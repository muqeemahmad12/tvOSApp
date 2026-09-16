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
        screenid = JSONNullTolerant.optionalString(container, .screenid)
        status = JSONNullTolerant.optionalString(container, .status)
        // Decode groups lossily so one bad sequence does not fail the whole quest.
        item1 = JSONNullTolerant.decodeArray(from: container, forKey: .item1)
    }
}

// MARK: - Sequence group — can contain 1–3 ads
struct AdSequenceGroup: Codable, Identifiable, Equatable {
    var id: Int { sequence }
    let facilityid: String
    let sequence: Int
    var ii: [AdItemModel]
    let is_active: Bool

    enum CodingKeys: String, CodingKey {
        case facilityid, sequence, ii, is_active
    }

    init(facilityid: String, sequence: Int, ii: [AdItemModel], is_active: Bool) {
        self.facilityid = facilityid
        self.sequence = sequence
        self.ii = ii
        self.is_active = is_active
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        facilityid = JSONNullTolerant.optionalString(container, .facilityid) ?? ""
        if let i = JSONNullTolerant.optionalInt(container, .sequence) {
            sequence = i
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .sequence,
                in: container,
                debugDescription: "sequence is required to order playback"
            )
        }
        ii = JSONNullTolerant.decodeArray(from: container, forKey: .ii)
        is_active = JSONNullTolerant.optionalBool(container, .is_active) ?? true
    }
    
    static func == (lhs: AdSequenceGroup, rhs: AdSequenceGroup) -> Bool {
        lhs.sequence == rhs.sequence
    }
}

// MARK: - Ad Item
struct AdItemModel: Codable, Identifiable, Equatable {
    /// Prefer itemid; fall back to URL so null-itemid flex/dummy creatives stay unique in UI.
    var id: String { itemid.isEmpty ? itemurl : itemid }

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
        scheduleendtime: String? = nil
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Everything may be null except we need a URL + asset type to play (enforced in displayableGroups).
        itemid = JSONNullTolerant.optionalString(container, .itemid) ?? ""
        assettype = JSONNullTolerant.optionalString(container, .assettype) ?? ""
        assetcat = JSONNullTolerant.optionalString(container, .assetcat)
        itemurl = JSONNullTolerant.optionalString(container, .itemurl) ?? ""
        itemsize = JSONNullTolerant.optionalString(container, .itemsize)
        duration = JSONNullTolerant.optionalInt(container, .duration)
        isFlex = JSONNullTolerant.optionalBool(container, .isFlex)
        trackerlist = JSONNullTolerant.decodeStringArray(from: container, forKey: .trackerlist)
        itemspeciality = JSONNullTolerant.optionalString(container, .itemspeciality)
        subcampaignid = JSONNullTolerant.optionalString(container, .subcampaignid)
        schedulestarttime = JSONNullTolerant.optionalString(container, .schedulestarttime)
        scheduleendtime = JSONNullTolerant.optionalString(container, .scheduleendtime)
    }

    static func == (lhs: AdItemModel, rhs: AdItemModel) -> Bool {
        lhs.itemid == rhs.itemid && lhs.itemurl == rhs.itemurl
    }
}

// MARK: - Null-tolerant JSON helpers
private enum JSONNullTolerant {
    static func optionalString<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String? {
        if c.contains(key), (try? c.decodeNil(forKey: key)) == true { return nil }
        if let s = try? c.decode(String.self, forKey: key) { return s }
        if let i = try? c.decode(Int.self, forKey: key) { return String(i) }
        if let d = try? c.decode(Double.self, forKey: key) { return String(d) }
        return nil
    }

    static func optionalInt<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
        if c.contains(key), (try? c.decodeNil(forKey: key)) == true { return nil }
        if let i = try? c.decode(Int.self, forKey: key) { return i }
        if let s = try? c.decode(String.self, forKey: key) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(trimmed)
        }
        if let d = try? c.decode(Double.self, forKey: key) { return Int(d) }
        return nil
    }

    static func optionalBool<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Bool? {
        if c.contains(key), (try? c.decodeNil(forKey: key)) == true { return nil }
        if let b = try? c.decode(Bool.self, forKey: key) { return b }
        if let i = try? c.decode(Int.self, forKey: key) { return i != 0 }
        if let s = try? c.decode(String.self, forKey: key) {
            switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "y": return true
            case "0", "false", "no", "n": return false
            default: return nil
            }
        }
        return nil
    }

    static func decodeStringArray<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> [String]? {
        if !container.contains(key) || (try? container.decodeNil(forKey: key)) == true {
            return nil
        }
        if let strings = try? container.decode([String].self, forKey: key) {
            return strings
        }
        // Mixed / partial arrays — keep only string elements.
        let parsed: [String] = decodeArray(from: container, forKey: key)
        return parsed.isEmpty ? nil : parsed
    }

    static func decodeArray<T: Decodable, K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> [T] {
        guard container.contains(key),
              (try? container.decodeNil(forKey: key)) != true,
              var unkeyed = try? container.nestedUnkeyedContainer(forKey: key) else {
            return []
        }
        var items: [T] = []
        while !unkeyed.isAtEnd {
            if let value = try? unkeyed.decode(T.self) {
                items.append(value)
            } else {
                // Advance past a bad element.
                _ = try? unkeyed.decode(LossyJSONValue.self)
            }
        }
        return items
    }
}

/// Consumes any JSON value so unkeyed decode can skip corrupt elements.
private struct LossyJSONValue: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { return }
        if (try? c.decode(Bool.self)) != nil { return }
        if (try? c.decode(Int.self)) != nil { return }
        if (try? c.decode(Double.self)) != nil { return }
        if (try? c.decode(String.self)) != nil { return }
        if (try? c.decode([LossyJSONValue].self)) != nil { return }
        if (try? c.decode([String: LossyJSONValue].self)) != nil { return }
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
    private static let playableImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic"
    ]
    private static let playableVideoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mpg", "mpeg", "m3u8"
    ]

    /// Only `image` and `video` are shown on the player (e.g. `Banner` is not displayable).
    var isDisplayableAsset: Bool {
        let type = assettype.lowercased()
        return type == "image" || type == "video"
    }

    /// File extension from `itemurl` (lowercased).
    var mediaPathExtension: String {
        URL(string: itemurl.trimmingCharacters(in: .whitespacesAndNewlines))?
            .pathExtension
            .lowercased() ?? ""
    }

    /// True when URL extension matches a real image/video file (rejects zip/html/etc.).
    var hasPlayableMediaExtension: Bool {
        let ext = mediaPathExtension
        guard !ext.isEmpty else { return false }
        switch assettype.lowercased() {
        case "image":
            return Self.playableImageExtensions.contains(ext)
        case "video":
            return Self.playableVideoExtensions.contains(ext)
        default:
            return false
        }
    }

    /// Minimum fields needed to attempt playback: image|video + URL + playable media extension.
    var hasMinimumPlayableFields: Bool {
        isDisplayableAsset
            && !itemurl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasPlayableMediaExtension
    }

    var isVideoType: Bool { assettype.lowercased() == "video" }
    var isImageType: Bool { assettype.lowercased() == "image" }
}

extension AdSequenceGroup {
    /// Index of the main L-shape creative: playable video, else any video slot.
    var lShapeMainIndex: Int? {
        if let playable = ii.firstIndex(where: { $0.isVideoType && $0.hasMinimumPlayableFields }) {
            return playable
        }
        return ii.firstIndex(where: { $0.isVideoType })
    }

    /// Items that occupy bottom/right (everything except the main video slot), in API order.
    var lShapeCompanions: [AdItemModel] {
        guard let mainIdx = lShapeMainIndex else { return ii }
        return ii.enumerated().compactMap { idx, ad in idx == mainIdx ? nil : ad }
    }
}

extension Array where Element == AdSequenceGroup {
    /// Keep groups that still have at least one playable creative.
    /// Required: `assettype` image|video + non-empty `itemurl`. Everything else may be null.
    ///
    /// Single-item groups: unplayable items are dropped.
    /// Multi-item (L-shape) groups: unplayable slots are kept so the UI can show white
    /// in that place (e.g. HTML5 `.zip`) while other playable slots still play.
    func displayableGroups() -> [AdSequenceGroup] {
        compactMap { group in
            let playable = group.ii.filter { $0.hasMinimumPlayableFields }
            guard !playable.isEmpty else { return nil }

            if group.ii.count >= 2 {
                // Preserve slot order/count for L-shape white placeholders.
                return group
            }

            var copy = group
            copy.ii = playable
            return copy
        }
    }
}
