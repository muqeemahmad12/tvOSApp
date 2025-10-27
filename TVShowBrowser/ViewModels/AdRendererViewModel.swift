//
//  AdRendererViewModel.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import Foundation
import Combine

class AdRendererViewModel: ObservableObject {
    @Published var currentAd: UIAdType?
    private var ads: [UIAdType] = []
    private var currentIndex = 0
    private var timer: AnyCancellable?

    init() {
        loadLocalAds()
    }

    func loadLocalAds() {
        guard let url = Bundle.main.url(forResource: "ads", withExtension: "json") else {
            print("❌ ads.json not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let remoteAds = try JSONDecoder().decode([RemoteAd].self, from: data)
            self.ads = remoteAds.compactMap { ad in
                switch ad.type.lowercased() {
                case "image":
                    return ad.url.map { .image(url: $0) }
                case "video":
                    return ad.url.map { .video(url: $0) }
                case "lottie":
                    return ad.name.map { .lottie(name: $0) }
                case "vast":
                    return ad.url.map { .video(url: $0) }
                default:
                    return nil
                }
            }

            startRotation()
        } catch {
            print("❌ Failed to parse ads.json:", error)
        }
    }

    func startRotation() {
        guard !ads.isEmpty else { return }
        currentAd = ads.first

        timer?.cancel()
        timer = Timer.publish(every: 12, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.showNextAd()
            }
    }

    func showNextAd() {
        guard !ads.isEmpty else { return }
        currentIndex = (currentIndex + 1) % ads.count
        currentAd = ads[currentIndex]
    }

    deinit {
        timer?.cancel()
    }
}

struct RemoteAd: Decodable {
    let type: String
    let url: String?
    let name: String?
    let html: String?
}
