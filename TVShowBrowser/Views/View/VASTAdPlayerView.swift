//
//  VASTAdPlayerView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 14/10/25.
//

import SwiftUI
import AVKit
import GoogleInteractiveMediaAds

struct VASTPlayerView: UIViewControllerRepresentable {
    let contentURL: URL
    let adTagURL: String
    @Binding var adProgress: Float
    @Binding var isPlayingContent: Bool
    
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = AdContainerController()
        controller.contentURL = contentURL
        controller.adTagURL = adTagURL
        controller.adProgress = $adProgress
        controller.isPlayingContent = $isPlayingContent
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    // MARK: - Controller Class

    class AdContainerController: UIViewController, IMAAdsLoaderDelegate, IMAAdsManagerDelegate {
        var contentURL: URL!
        var adTagURL: String!
        var adProgress: Binding<Float>!
        var isPlayingContent: Binding<Bool>!

        private var player: AVPlayer!
        private var playerVC: AVPlayerViewController!
        private var adsLoader: IMAAdsLoader!
        private var adsManager: IMAAdsManager?
        private var contentPlayhead: IMAAVPlayerContentPlayhead!
        private var playerTimeObserver: Any?
        private var hasRequestedAds = false
        private var controlsVisible = true
        private var controlsTimer: Timer?

        private var currentAd: IMAAd?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            setupContentPlayer()
            setupAdsLoader()
            getScreenSize()
        }
         
        func getScreenSize() {
            
            let screenBounds = UIScreen.main.bounds
            let width = screenBounds.width
            let height = screenBounds.height

            print("Screen size in points: \(width)x\(height)")

            let nativeWidth = UIScreen.main.nativeBounds.width
            let nativeHeight = UIScreen.main.nativeBounds.height

            print("Screen size in pixels: \(nativeWidth)x\(nativeHeight)")

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                let safeAreaInsets = window.safeAreaInsets
                print("Safe area insets: \(safeAreaInsets)")
            }

            if #available(tvOS 16.0, *) {
                print(ProcessInfo.processInfo.operatingSystemVersionString)
            }

            
        }
        class FocusableView: UIView {
            override var canBecomeFocused: Bool { true }
        }

        private func setupContentPlayer() {
            let firstVideo = AVPlayerItem(url: contentURL)
            let secondVideo = AVPlayerItem(url: URL(string: "https://storage.googleapis.com/interactive-media-ads/media/android.mp4")!)
            player = AVQueuePlayer(items: [firstVideo, secondVideo])

//            player = AVPlayer(url: contentURL)
            playerVC = AVPlayerViewController()
            playerVC.player = player
            playerVC.showsPlaybackControls = false

            addChild(playerVC)
            view.addSubview(playerVC.view)
            playerVC.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                playerVC.view.topAnchor.constraint(equalTo: view.topAnchor),
                playerVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                playerVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                playerVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            playerVC.didMove(toParent: self)
        }

        // Focus animation
        override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            if let next = context.nextFocusedView as? UIButton {
                coordinator.addCoordinatedAnimations {
                    next.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
                }
            }

            if let previous = context.previouslyFocusedView as? UIButton {
                coordinator.addCoordinatedAnimations {
                    previous.transform = .identity
                }
            }
        }

        override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
            // Allow all focus updates
            return true
        }
        
        private func setupAdsLoader() {
            adsLoader = IMAAdsLoader(settings: nil)
            adsLoader.delegate = self
            let adDisplayContainer = IMAAdDisplayContainer(adContainer: view, viewController: self)
            contentPlayhead = IMAAVPlayerContentPlayhead(avPlayer: player)
            let request = IMAAdsRequest(
                adTagUrl: adTagURL,
                adDisplayContainer: adDisplayContainer,
                contentPlayhead: contentPlayhead,
                userContext: nil
            )
            adsLoader.requestAds(with: request)
        }

        // MARK: - IMAAdsLoaderDelegate
        func adsLoader(_ loader: IMAAdsLoader, adsLoadedWith adsLoadedData: IMAAdsLoadedData) {
            adsManager = adsLoadedData.adsManager
            adsManager?.delegate = self
            let settings = IMAAdsRenderingSettings()
            adsManager?.initialize(with: settings)
        }

        func adsLoader(_ loader: IMAAdsLoader, failedWith adErrorData: IMAAdLoadingErrorData) {
            print("❌ Failed to load ads: \(adErrorData.adError.message ?? "Unknown error")")
            player.play()
            startContentProgressObserver()
        }

        // MARK: - IMAAdsManagerDelegate
        func adsManager(_ adsManager: IMAAdsManager, didReceive event: IMAAdEvent) {
            switch event.type {
            case .STARTED:
                currentAd = event.ad

            case .COMPLETE, .ALL_ADS_COMPLETED:
                currentAd = nil
                player.play()
                startContentProgressObserver()

            default: break
            }
        }

        func adsManager(_ adsManager: IMAAdsManager, didReceive error: IMAAdError) {
            print("⚠️ AdsManager error: \(error.message ?? "Unknown")")
            player.play()
            startContentProgressObserver()
        }

        func adsManagerDidRequestContentPause(_ adsManager: IMAAdsManager) {
            stopContentProgressObserver()
        }

        func adsManagerDidRequestContentResume(_ adsManager: IMAAdsManager) {
            player.play()
            startContentProgressObserver()
        }

        func adsManager(_ adsManager: IMAAdsManager, adDidProgressToTime mediaTime: TimeInterval, totalTime: TimeInterval) {
            guard totalTime > 0 else { return }
            let progress = Float(mediaTime / totalTime)
            DispatchQueue.main.async {
                self.adProgress.wrappedValue = min(max(progress, 0), 1)
            }
        }

        // MARK: - Content Progress Tracking
        private func startContentProgressObserver() {
            stopContentProgressObserver()
            guard let item = player.currentItem else { return }
            let duration = item.asset.duration.seconds
            guard duration.isFinite && duration > 0 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.startContentProgressObserver() }
                return
            }

            playerTimeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                guard let self = self else { return }
                let progress = Float(time.seconds / duration)
                self.adProgress.wrappedValue = min(max(progress, 0), 1)
            }
        }

        private func stopContentProgressObserver() {
            if let obs = playerTimeObserver {
                player.removeTimeObserver(obs)
                playerTimeObserver = nil
            }
        }

        deinit {
            stopContentProgressObserver()
            adsManager?.destroy()
            controlsTimer?.invalidate()
        }
    }

}
