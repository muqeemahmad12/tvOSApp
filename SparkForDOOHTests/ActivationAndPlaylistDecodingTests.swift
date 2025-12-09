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
}
