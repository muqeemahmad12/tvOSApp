//
//  VASTAdPlayerViewModel.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 14/10/25.
//

import SwiftUI
import AVKit
import GoogleInteractiveMediaAds
import AVFoundation

// MARK: - SwiftUI VAST Player ViewModel
final class VASTAdPlayerViewModel: NSObject, ObservableObject {
    // MARK: Properties
    private var adsLoader: IMAAdsLoader!
    private var adsManager: IMAAdsManager?
    private var adDisplayContainer: IMAAdDisplayContainer?
    private var adBreakActive = false
    private var containerView: UIView?

    var contentPlayhead: IMAAVPlayerContentPlayhead?
    var playerViewController: AVPlayerViewController!

    // Sample Google content & VAST URL
    private let contentURLString =
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"
    private let adTagURLString =
        "https://pubads.g.doubleclick.net/gampad/ads?iu=/21775744923/external/single_ad_samples&sz=640x480&cust_params=sample_ct%3Dlinear&ciu_szs=300x250%2C728x90&gdfp_req=1&output=vast&unviewed_position_start=1&env=vp&correlator="

    override init() {
        super.init()
        configureAudioSession()
        setUpContentPlayer()
        setUpAdsLoader()
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    // MARK: Content Player
    private func setUpContentPlayer() {
        let url = URL(string: contentURLString)!
        let player = AVPlayer(url: url)
        playerViewController = AVPlayerViewController()
        playerViewController.player = player

        contentPlayhead = IMAAVPlayerContentPlayhead(avPlayer: player)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
    }

    @objc private func contentDidFinishPlaying() {
        adsLoader.contentComplete()
    }

    // MARK: Ads Loader
    private func setUpAdsLoader() {
        adsLoader = IMAAdsLoader(settings: nil)
        adsLoader.delegate = self
    }

    func requestAds(into containerView: UIView) {
        self.containerView = containerView
        let adDisplayContainer = IMAAdDisplayContainer(adContainer: containerView, viewController: playerViewController)

        let request = IMAAdsRequest(
            adTagUrl: adTagURLString,
            adDisplayContainer: adDisplayContainer,
            contentPlayhead: contentPlayhead,
            userContext: nil
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.adsLoader.requestAds(with: request)
        }
    }

    // MARK: Focus Helper
    func isAdPlaying() -> Bool {
        return adBreakActive
    }
}

// MARK: - IMA Delegates
extension VASTAdPlayerViewModel: IMAAdsLoaderDelegate, IMAAdsManagerDelegate {
    func adsLoader(_ loader: IMAAdsLoader, adsLoadedWith adsLoadedData: IMAAdsLoadedData) {
        adsManager = adsLoadedData.adsManager
        adsManager?.delegate = self
        adsManager?.initialize(with: nil)
    }

    func adsLoader(_ loader: IMAAdsLoader, failedWith adErrorData: IMAAdLoadingErrorData) {
        print("Error loading ads: \(adErrorData.adError.message ?? "No message")")
        containerView?.addSubview(playerViewController.view)
        playerViewController.player?.play()
    }

    func adsManager(_ adsManager: IMAAdsManager, didReceive event: IMAAdEvent) {
        switch event.type {
        case .LOADED:
            adsManager.start()
        default:
            break
        }
    }

    func adsManager(_ adsManager: IMAAdsManager, didReceive error: IMAAdError) {
        print("AdsManager error: \(error.message ?? "No message")")
        containerView?.addSubview(playerViewController.view)
        playerViewController.player?.play()
    }

    func adsManagerDidRequestContentPause(_ adsManager: IMAAdsManager) {
        playerViewController.player?.pause()
        adBreakActive = true
    }

    func adsManagerDidRequestContentResume(_ adsManager: IMAAdsManager) {
        adBreakActive = false
        playerViewController.player?.play()
    }
}
