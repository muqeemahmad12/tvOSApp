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

        APIService.shared.fetchItemSeqInfo(screenId: screenId, reqNum: reqNum) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false

                switch result {
                case .success(let response):
                    // ✅ Keep both grouped and flat
                    let groups = response.groupedAds
                    self.groupedAds = groups
                    self.ads = groups.flatMap { $0.ii }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    print("❌ API Failed:", error.localizedDescription)
                }
            }
        }
    }
}
