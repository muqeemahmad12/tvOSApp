//
//  AdItemModel.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import Foundation

// MARK: - Item Sequence Response
struct ItemSeqInfoResponse: Codable {
    let status: String
    let screenid: String
    let items: [AdItemModel]
}

struct AdItemModel: Codable, Identifiable, Equatable {
    var id: String { itemid }

    let itemid: String
    let assettype: String
    let assetcat: String?
    let itemurl: String
    let itemsize: String
    let isFlex: Bool
    let trackerlist: [String]
    let isActive: Bool
    let facilityid: String
    let itemspeciality: String
    let sequence: Int
    let schedulestarttime: String?
    let scheduleendtime: String?
    let subcampaignid: String

    enum CodingKeys: String, CodingKey {
        case itemid, assettype, assetcat, itemurl, itemsize
        case isFlex = "is_flex"
        case trackerlist
        case isActive = "is_active"
        case facilityid, itemspeciality, sequence, schedulestarttime, scheduleendtime, subcampaignid
    }

    // ✅ Optional but helps define equality clearly
    static func == (lhs: AdItemModel, rhs: AdItemModel) -> Bool {
        lhs.itemid == rhs.itemid && lhs.sequence == rhs.sequence
    }
}
