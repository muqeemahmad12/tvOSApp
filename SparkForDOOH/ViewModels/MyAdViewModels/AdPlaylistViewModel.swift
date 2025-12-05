//
//  AdPlaylistViewModel.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import Foundation
import Combine

@MainActor
final class AdPlaylistViewModel: ObservableObject {
    @Published var ads: [AdItemModel] = []                // Flattened list (optional)
    @Published var groupedAds: [AdSequenceGroup] = []     // Grouped list (1–3 per sequence)
    @Published var isLoading = false
    @Published var errorMessage: String?

    func fetchAds(screenId: String, reqNum: Int) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let response = try await APIService.shared.fetchItemSeqInfo(screenId: screenId,
                                                                            reqNum: reqNum)
                let groups = response.groupedAds
                groupedAds = groups
                ads = groups.flatMap { $0.ii }
            } catch {
                errorMessage = error.localizedDescription
                print("❌ API Failed:", error.localizedDescription)
            }

            isLoading = false
        }
    }
}
