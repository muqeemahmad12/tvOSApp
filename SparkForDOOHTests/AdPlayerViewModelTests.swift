//
//  AdPlayerViewModelTestsOne.swift
//  SparkForDOOHTests
//
//  Created by Muqeem Ahmad on 09/12/25.
//

import XCTest
@testable import SparkForDOOH

@MainActor
final class AdPlayerViewModelTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func makeGroup(sequence: Int, items: [AdItemModel]) -> AdSequenceGroup {
        AdSequenceGroup(facilityid: "F1", sequence: sequence, ii: items, is_active: true)
    }

    func makeImage(id: String, url: String) -> AdItemModel {
        AdItemModel(
            itemid: id,
            assettype: "image",
            assetcat: nil,
            itemurl: url,
            itemsize: nil,
            isFlex: nil,
            trackerlist: nil,
            itemspeciality: nil,
            subcampaignid: nil,
            schedulestarttime: nil,
            scheduleendtime: nil,
            sequence: nil,
            facilityid: nil
        )
    }

    func makeVideo(id: String, url: String) -> AdItemModel {
        AdItemModel(
            itemid: id,
            assettype: "video",
            assetcat: nil,
            itemurl: url,
            itemsize: nil,
            isFlex: nil,
            trackerlist: nil,
            itemspeciality: nil,
            subcampaignid: nil,
            schedulestarttime: nil,
            scheduleendtime: nil,
            sequence: nil,
            facilityid: nil
        )
    }

    func testStartPlaybackWithSingleImageGroup() async {
        let vm = AdPlayerViewModel(disablePreloadingAndValidation: true)
        let image = makeImage(id: "1", url: "https://example.com/img1.jpg")
        let group = makeGroup(sequence: 1, items: [image])

        vm.startPlayback(with: [group])

        XCTAssertEqual(vm.groupedAds.count, 1)
        XCTAssertEqual(vm.currentGroup?.sequence, 1)
    }

    func testStartPlaybackWithImageAndVideoGroup() async {
        let vm = AdPlayerViewModel(disablePreloadingAndValidation: true)
        let image = makeImage(id: "1", url: "https://example.com/img1.jpg")
        let video = makeVideo(id: "2", url: "https://example.com/vid1.mp4")
        let group = makeGroup(sequence: 1, items: [image, video])

        vm.startPlayback(with: [group])

        XCTAssertEqual(vm.groupedAds.count, 1)
        XCTAssertEqual(vm.currentGroup?.ii.count, 2)
    }

    func testStartPlaybackWithEmptyPlaylistDoesNothing() async {
        let vm = AdPlayerViewModel(disablePreloadingAndValidation: true)

        vm.startPlayback(with: [])

        XCTAssertNil(vm.currentGroup)
        XCTAssertTrue(vm.groupedAds.isEmpty)
    }
}
