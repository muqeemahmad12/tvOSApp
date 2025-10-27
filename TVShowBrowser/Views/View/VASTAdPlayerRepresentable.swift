//
//  VASTAdPlayerRepresentable.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 17/10/25.
//

import Foundation
import AVFoundation
import AVKit
import SwiftUI

// MARK: - Models

public struct VASTAd {
    public var id: String?
    public var universalAdIDs: [String] = []
    public var title: String?
    public var description: String?
    public var mediaFileURL: URL?
    public var clickThroughURL: URL?
    public var impressionURLs: [URL] = []
    public var viewableImpressionURLs: [URL] = []
    public var trackingEvents: [String: [URL]] = [:] // eventName -> [urls]
}

// MARK: - VAST Parser (simple, supports wrapper resolution externally)

final class VASTParser: NSObject, XMLParserDelegate {
    private var parser: XMLParser
    private var currentAd = VASTAd()
    private var ads: [VASTAd] = []
    private var currentElement = ""
    private var foundCharacters = ""
    private var currentTrackingEvent: String?
    private var insideWrapper = false
    private var wrapperAdTagURI: String?

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func parse() -> ([VASTAd], String?) {
        parser.parse()
        // Return ads and optional wrapperAdTagURI (if parser found <VASTAd> wrapper)
        return (ads, wrapperAdTagURI)
    }

    // MARK: - XMLParserDelegate
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        foundCharacters = ""

        switch currentElement {
        case "ad":
            currentAd = VASTAd()
            if let id = attributeDict["id"] { currentAd.id = id }
        case "mediafile":
            // check attributes for delivery or url attr
            if let urlStr = attributeDict["url"] ?? attributeDict["src"], let url = URL(string: urlStr) {
                currentAd.mediaFileURL = url
            } else if let type = attributeDict["type"], type.contains("video") {
                // we'll parse body text later
            }
        case "tracking":
            currentTrackingEvent = attributeDict["event"]
        case "wrapper":
            insideWrapper = true
        case "vst:vastadtaguri", "vastadtaguri", "vastadtaguri": // wrapper redirect tag names vary by namespace
            // body might contain the URI
            break
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        foundCharacters += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let tag = elementName.lowercased()
        let trimmed = foundCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
        switch tag {
        case "ad":
            ads.append(currentAd)
            currentAd = VASTAd()
            insideWrapper = false
        case "title":
            if currentElement == "title" { currentAd.title = trimmed }
        case "description":
            currentAd.description = trimmed
        case "mediafile":
            if currentAd.mediaFileURL == nil, let u = URL(string: trimmed) {
                currentAd.mediaFileURL = u
            }
        case "impression":
            if let url = URL(string: trimmed) { currentAd.impressionURLs.append(url) }
        case "viewableimpression":
            // Some VASTs may have child URL nodes; try to parse body
            if let url = URL(string: trimmed) { currentAd.viewableImpressionURLs.append(url) }
        case "clickthrough":
            if let url = URL(string: trimmed) { currentAd.clickThroughURL = url }
        case "tracking":
            if let event = currentTrackingEvent, let url = URL(string: trimmed) {
                var arr = currentAd.trackingEvents[event] ?? []
                arr.append(url)
                currentAd.trackingEvents[event] = arr
            }
            currentTrackingEvent = nil
        case "universaladid":
            if !trimmed.isEmpty { currentAd.universalAdIDs.append(trimmed) }
        case "vastadtaguri", "vst:vastadtaguri":
            if insideWrapper {
                wrapperAdTagURI = trimmed
            }
        default:
            break
        }
        foundCharacters = ""
    }
}

// MARK: - VAST Ad Loader (follows wrapper up to maxDepth)

final class VASTAdLoader {
    let session: URLSession
    let maxWrapperDepth: Int

    init(session: URLSession = .shared, maxWrapperDepth: Int = 3) {
        self.session = session
        self.maxWrapperDepth = maxWrapperDepth
    }

    /// Loads a VAST ad by fetching and following wrappers. Completion returns first parsed VASTAd or error.
    func loadAd(from urlString: String, completion: @escaping (Result<VASTAd, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "VAST", code: -1, userInfo: [NSLocalizedDescriptionKey: "Bad URL"])))
            return
        }
        fetch(url: url, depth: 0, completion: completion)
    }

    private func fetch(url: URL, depth: Int, completion: @escaping (Result<VASTAd, Error>) -> Void) {
        if depth > maxWrapperDepth {
            completion(.failure(NSError(domain: "VAST", code: -2, userInfo: [NSLocalizedDescriptionKey: "Too many wrappers"])))
            return
        }

        let task = session.dataTask(with: url) { data, response, error in
            if let e = error { completion(.failure(e)); return }
            guard let data = data else {
                completion(.failure(NSError(domain: "VAST", code: -3, userInfo: [NSLocalizedDescriptionKey: "Empty response"])))
                return
            }

            let parser = VASTParser(data: data)
            let (ads, wrapperUri) = parser.parse()

            // If wrapperUri found, follow it (wrapper scenario)
            if let wrapper = wrapperUri, let wrapperURL = URL(string: wrapper), !wrapper.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Merge trackers from wrapper if necessary? For POC, follow wrapper to resolve to an InLine ad.
                self.fetch(url: wrapperURL, depth: depth + 1, completion: completion)
                return
            }

            // Select first ad having media file
            if let ad = ads.first(where: { $0.mediaFileURL != nil }) {
                completion(.success(ad))
            } else if let first = ads.first {
                // If no media but ad exists (e.g., VPAID), return it for higher-level handler to process
                completion(.success(first))
            } else {
                completion(.failure(NSError(domain: "VAST", code: -4, userInfo: [NSLocalizedDescriptionKey: "No playable ad found"])))
            }
        }
        task.resume()
    }
}

// MARK: - VAST Tracker (simple GET firing with optional retry)

final class VASTTracker {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fire(urls: [URL]) {
        for url in urls {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            // Do not wait for response
            let task = session.dataTask(with: request) { _, _, _ in /* no-op */ }
            task.resume()
        }
    }

    func fire(url: URL?) {
        guard let u = url else { return }
        fire(urls: [u])
    }
}

// MARK: - Simple VAST Ad Player (AVPlayer + quartile tracking)

final class VASTAdPlayerViewController: UIViewController {
    private var player: AVPlayer?
    private var playerVC: AVPlayerViewController!
    private var ad: VASTAd
    private var tracker = VASTTracker()
    private var periodicObserver: Any?
    private var quartilesFired = Set<String>()

    init(ad: VASTAd) {
        self.ad = ad
        super.init(nibName: nil, bundle: nil)
    }

    deinit {
        if let obs = periodicObserver { player?.removeTimeObserver(obs) }
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        playerVC = AVPlayerViewController()
        addChild(playerVC)
        view.addSubview(playerVC.view)
        playerVC.view.frame = view.bounds
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerVC.didMove(toParent: self)

        guard let mediaURL = ad.mediaFileURL else {
            // fallback: no media (VPAID or other). In real app, hand off to IMA/VPAID flow.
            print("No linear media file in ad — hand off to IMA/VPAID if applicable")
            return
        }

        player = AVPlayer(url: mediaURL)
        playerVC.player = player

        // fire impressions immediately
        tracker.fire(urls: ad.impressionURLs)
        tracker.fire(urls: ad.viewableImpressionURLs)

        // fire start trackers if present
        tracker.fire(urls: ad.trackingEvents["start"] ?? [])

        addPeriodicObserver()
        NotificationCenter.default.addObserver(self, selector: #selector(didFinishPlaying(_:)), name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)

        // autoplay
        player?.play()
    }

    @objc private func didFinishPlaying(_ n: Notification) {
        tracker.fire(urls: ad.trackingEvents["complete"] ?? [])
        // Optionally dismiss or notify delegate
    }

    private func addPeriodicObserver() {
        guard let player = player, let duration = player.currentItem?.asset.duration.seconds, duration.isFinite, duration > 0 else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        periodicObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.handleTime(time: time)
        }
    }

    private func handleTime(time: CMTime) {
        guard let player = player, let duration = player.currentItem?.duration.seconds, duration.isFinite && duration > 0 else { return }
        let current = time.seconds
        let pct = current / duration

        if pct >= 0.25 && !quartilesFired.contains("firstQuartile") {
            quartilesFired.insert("firstQuartile")
            tracker.fire(urls: ad.trackingEvents["firstQuartile"] ?? [])
        }
        if pct >= 0.5 && !quartilesFired.contains("midpoint") {
            quartilesFired.insert("midpoint")
            tracker.fire(urls: ad.trackingEvents["midpoint"] ?? [])
        }
        if pct >= 0.75 && !quartilesFired.contains("thirdQuartile") {
            quartilesFired.insert("thirdQuartile")
            tracker.fire(urls: ad.trackingEvents["thirdQuartile"] ?? [])
        }
    }
}

// MARK: - SwiftUI convenience wrapper for quick integration

//struct VASTAdPlayerRepresentable: UIViewControllerRepresentable {
//    let vastTagURL: String
//    private let loader = VASTAdLoader()
//
//    func makeUIViewController(context: Context) -> UIViewController {
//        let placeholder = UIViewController()
//        placeholder.view.backgroundColor = .black
//
//        loader.loadAd(from: vastTagURL) { result in
//            DispatchQueue.main.async {
//                switch result {
//                case .success(let ad):
//                    // if linear media exists, present our VASTAdPlayerViewController
//                    if ad.mediaFileURL != nil {
//                        let adVC = VASTAdPlayerViewController(ad: ad)
//                        adVC.modalPresentationStyle = .fullScreen
//                        placeholder.present(adVC, animated: false)
//                    } else {
//                        // for non-linear or VPAID, hand off to IMA or other handler
//                        print("Ad has no linear media — hand off to IMA/VPAID path")
//                    }
//                case .failure(let error):
//                    print("VAST load failed: \(error.localizedDescription)")
//                }
//            }
//        }
//
//        return placeholder
//    }
//
//    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
//}
