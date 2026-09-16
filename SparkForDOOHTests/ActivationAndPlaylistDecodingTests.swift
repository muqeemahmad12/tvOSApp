//
//  TestOne.swift
//  SparkForDOOHTests
//
//  Created by Muqeem Ahmad on 09/12/25.
//

import XCTest
@testable import SparkForDOOH

final class ActivationAndPlaylistDecodingTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testActivationResponseDecoding() throws {
        let json = """
        {
          "timestamp": "2025-12-03T10:00:00Z",
          "code": 200,
          "status": "SUCCESS",
          "message": "OK",
          "data": {
            "deviceCode": "DEV-123",
            "userCode": "ABC123",
            "status": "PENDING",
            "expiresAt": "2025-12-03T11:00:00Z"
          }
        }
        """

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ActivationResponse.self, from: data)

        XCTAssertEqual(decoded.code, 200)
        XCTAssertEqual(decoded.status, "SUCCESS")
        XCTAssertEqual(decoded.data?.deviceCode, "DEV-123")
        XCTAssertEqual(decoded.data?.userCode, "ABC123")
    }

    func testItemSeqInfoResponseGroupedAdsFiltersAndSorts() throws {
        let json = """
        {
          "screenid": "174",
          "status": "OK",
          "item1": [
            {
              "facilityid": "F1",
              "sequence": 2,
              "ii": [],
              "is_active": true
            },
            {
              "facilityid": "F1",
              "sequence": 1,
              "ii": [],
              "is_active": false
            }
          ]
        }
        """

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ItemSeqInfoResponse.self, from: data)

        let groups = decoded.groupedAds
        XCTAssertEqual(groups.count, 1, "Only active groups should be returned")
        XCTAssertEqual(groups.first?.sequence, 2, "Groups should be sorted by sequence ascending")
        XCTAssertTrue(groups.first?.is_active == true)
    }

    func testItemSeqInfoAllowsNullItemIdWithValidURL() throws {
        let json = """
        {
          "screenid": "174",
          "status": "OK",
          "item1": [
            {
              "facilityid": null,
              "sequence": 1,
              "is_active": true,
              "ii": [
                {
                  "assetcat": "o",
                  "itemsize": "1920 x 1080",
                  "schedulestarttime": null,
                  "subcampaignid": null,
                  "itemid": null,
                  "trackerlist": null,
                  "scheduleendtime": null,
                  "itemspeciality": null,
                  "assettype": "Image",
                  "itemurl": "https://simage.doceree.com/spark-dooh/assets/1920x1080.png",
                  "is_flex": false
                },
                {
                  "itemid": "47",
                  "assettype": "Image",
                  "itemurl": "https://example.com/a.png",
                  "duration": 15
                },
                {
                  "itemid": null,
                  "assettype": "Image",
                  "itemurl": null
                }
              ]
            }
          ]
        }
        """
        let decoded = try JSONDecoder().decode(ItemSeqInfoResponse.self, from: Data(json.utf8))
        let playable = decoded.item1.displayableGroups()
        XCTAssertEqual(playable.count, 1)
        // Multi-item L-shape: keep null-URL slot for white placeholder.
        XCTAssertEqual(playable.first?.ii.count, 3)
        XCTAssertEqual(playable.first?.ii.first?.itemid, "")
        XCTAssertTrue(playable.first?.ii.first?.hasMinimumPlayableFields ?? false)
        XCTAssertFalse(playable.first?.ii[2].hasMinimumPlayableFields ?? true)
    }

    func testUnplayableThirdKeepsOtherPlayableItems() throws {
        let json = """
        {
          "item1": [
            {
              "facilityid": "F1",
              "sequence": 1,
              "is_active": true,
              "ii": [
                {
                  "itemid": "v1",
                  "assettype": "video",
                  "itemurl": "https://example.com/main.mp4"
                },
                {
                  "itemid": "47",
                  "assettype": "Image",
                  "itemurl": "https://example.com/bottom.png"
                },
                {
                  "itemid": null,
                  "assettype": "Image",
                  "itemurl": null
                }
              ]
            }
          ]
        }
        """
        let decoded = try JSONDecoder().decode(ItemSeqInfoResponse.self, from: Data(json.utf8))
        let playable = decoded.item1.displayableGroups()
        XCTAssertEqual(playable.count, 1)
        // L-shape: keep unplayable third slot so UI can show white in place.
        XCTAssertEqual(playable.first?.ii.count, 3)
        XCTAssertEqual(playable.first?.ii.map { $0.assettype.lowercased() }, ["video", "image", "image"])
        XCTAssertFalse(playable.first?.ii[2].hasMinimumPlayableFields ?? true)
    }

    func testZipHtml5PackageIsNotPlayable() throws {
        let json = """
        {
          "item1": [
            {
              "facilityid": "F1",
              "sequence": 1,
              "is_active": true,
              "ii": [
                {
                  "itemid": "z1",
                  "assettype": "video",
                  "itemurl": "https://cdn.example.com/content_1779688607886_html5_zip_file_prime_brand.zip"
                }
              ]
            }
          ]
        }
        """
        let decoded = try JSONDecoder().decode(ItemSeqInfoResponse.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.item1.first?.ii.first?.hasMinimumPlayableFields ?? true)
        XCTAssertTrue(decoded.item1.displayableGroups().isEmpty)
    }

    func testLShapeKeepsZipSlotAsPlaceholder() throws {
        let json = """
        {
          "item1": [
            {
              "facilityid": "F1",
              "sequence": 1,
              "is_active": true,
              "ii": [
                {
                  "itemid": "v1",
                  "assettype": "video",
                  "itemurl": "https://example.com/main.mp4"
                },
                {
                  "itemid": "47",
                  "assettype": "Image",
                  "itemurl": "https://example.com/bottom.png"
                },
                {
                  "itemid": "z1",
                  "assettype": "Image",
                  "itemurl": "https://d3gglspuvl1a31.cloudfront.net/content/670/20260525/content_1779688607886_html5_zip_file_prime_brand.zip"
                }
              ]
            }
          ]
        }
        """
        let decoded = try JSONDecoder().decode(ItemSeqInfoResponse.self, from: Data(json.utf8))
        let groups = decoded.item1.displayableGroups()
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.ii.count, 3)
        XCTAssertTrue(groups.first?.ii[0].hasMinimumPlayableFields ?? false)
        XCTAssertTrue(groups.first?.ii[1].hasMinimumPlayableFields ?? false)
        XCTAssertFalse(groups.first?.ii[2].hasMinimumPlayableFields ?? true)
        XCTAssertEqual(groups.first?.lShapeCompanions.count, 2)
        XCTAssertFalse(groups.first?.lShapeCompanions[1].hasMinimumPlayableFields ?? true)
    }

    func testLShapeZipTypedAsVideoDoesNotReuseBottomImage() throws {
        let json = """
        {
          "item1": [
            {
              "facilityid": "F1",
              "sequence": 1,
              "is_active": true,
              "ii": [
                {
                  "itemid": "v1",
                  "assettype": "video",
                  "itemurl": "https://example.com/main.mp4"
                },
                {
                  "itemid": "47",
                  "assettype": "Image",
                  "itemurl": "https://example.com/bottom.png"
                },
                {
                  "itemid": "z1",
                  "assettype": "video",
                  "itemurl": "https://d3gglspuvl1a31.cloudfront.net/content/670/20260525/content_1779688607886_html5_zip_file_prime_brand.zip"
                }
              ]
            }
          ]
        }
        """
        let decoded = try JSONDecoder().decode(ItemSeqInfoResponse.self, from: Data(json.utf8))
        let group = try XCTUnwrap(decoded.item1.displayableGroups().first)
        XCTAssertEqual(group.ii.count, 3)
        let companions = group.lShapeCompanions
        XCTAssertEqual(companions.count, 2, "Zip video must stay as its own companion slot")
        XCTAssertTrue(companions[0].hasMinimumPlayableFields)
        XCTAssertFalse(companions[1].hasMinimumPlayableFields)
        XCTAssertNotEqual(companions[0].itemurl, companions[1].itemurl)
    }
}
