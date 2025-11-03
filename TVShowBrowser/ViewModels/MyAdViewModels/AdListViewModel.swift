//
//  AdListViewModel.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import Foundation
import Combine

@MainActor
final class AdListViewModel: ObservableObject {
    @Published var ads: [AdItemModel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func fetchAds(screenId: String) {
        isLoading = true
        errorMessage = nil

        APIService.shared.fetchItemSeqInfo(screenId: screenId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false

                switch result {
                case .success(let response):
                    print("✅ API Success — Total Items: \(response.items.count)")
                        response.items.forEach { item in
                            print("🔹 \(item.itemid): \(item.assettype) — \(item.itemurl) - \(item.itemsize)")
                        }
                    self.ads = response.items.sorted { $0.sequence < $1.sequence }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
