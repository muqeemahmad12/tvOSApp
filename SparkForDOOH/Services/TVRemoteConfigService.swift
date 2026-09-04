//
//  TVRemoteConfigService.swift
//  SparkForDOOH
//
//  QA / Dev / Prod come from which URLs are in tv-config — not from build flags.
//  Heartbeat & Sentry "environment" is derived from activation_base_url and drs_base_url hosts.
//

import Foundation

private struct TVRemoteConfigRoot: Decodable {
    let tvos: [String: TVRemoteConfigEntry]
}

private struct TVRemoteConfigEntry: Codable {
    let activation_base_url: String
    let drs_base_url: String
    let force_update: Bool
    /// Optional; if set, used for activation QR. Otherwise AppConfig.sparkPortalURL.
    let spark_portal_url: String?
}

private struct TVRemoteConfigPersisted: Codable {
    let activation_base_url: String
    let drs_base_url: String
    let force_update: Bool
    let config_key: String
    let spark_portal_url: String?
}

final class TVRemoteConfigStore {
    static let shared = TVRemoteConfigStore()

    private let lock = NSLock()
    private var _activationBaseString: String?
    private var _drsBaseString: String?
    private var _forceUpdate: Bool = false
    private var _sparkPortalURLFromRemote: String?
    private(set) var isLoaded: Bool = false
    private(set) var selectedKey: String = "plist"

    private init() {}

    var forceUpdate: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _forceUpdate
    }

    /// Identifies backend tier for heartbeat payload & Sentry: hosts from **activation** and **drs** tv-config URLs.
    /// Same host twice collapses to a single host; two hosts join as `host1|host2` (activation first).
    var environmentLabel: String {
        lock.lock()
        let act = _activationBaseString
        let drs = _drsBaseString
        lock.unlock()
        let actHost = act.flatMap { Self.host(fromNormalizedBase: $0) }
        let drsHost = drs.flatMap { Self.host(fromNormalizedBase: $0) }
        switch (actHost, drsHost) {
        case let (a?, d?) where a.caseInsensitiveCompare(d) == .orderedSame:
            return a
        case let (a?, d?):
            return "\(a)|\(d)"
        case let (a?, nil):
            return a
        case let (nil, d?):
            return d
        default:
            return "unknown"
        }
    }

    var sparkPortalURL: URL {
        lock.lock()
        let raw = _sparkPortalURLFromRemote
        lock.unlock()
        if let raw, !raw.isEmpty, let u = URL(string: raw) {
            return u
        }
        return AppConfig.current.sparkPortalURL
    }

    fileprivate func apply(entry: TVRemoteConfigEntry, key: String) {
        lock.lock()
        defer { lock.unlock() }
        _activationBaseString = Self.normalizeBaseURL(entry.activation_base_url)
        _drsBaseString = Self.normalizeBaseURL(entry.drs_base_url)
        _forceUpdate = entry.force_update
        let spark = entry.spark_portal_url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !spark.isEmpty, URL(string: spark) != nil {
            _sparkPortalURLFromRemote = spark
        } else {
            _sparkPortalURLFromRemote = nil
        }
        isLoaded = true
        selectedKey = key
    }

    private static func normalizeBaseURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Host from a stored base URL string (adds `https://` if there is no scheme so `URL` can parse).
    private static func host(fromNormalizedBase base: String) -> String? {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URL(string: withScheme)?.host, !host.isEmpty else { return nil }
        return host
    }

    func activationURL(pathComponents: String...) -> URL {
        lock.lock()
        let base = _activationBaseString
        lock.unlock()
        if let base, !base.isEmpty {
            let suffix = pathComponents.joined(separator: "/")
            if let url = URL(string: base + "/" + suffix) {
                return url
            }
        }
        var u = AppConfig.current.activationBaseURL
        for c in pathComponents {
            u = u.appendingPathComponent(c)
        }
        return u
    }

    func drsQuestURL() -> URL {
        lock.lock()
        let base = _drsBaseString
        lock.unlock()
        guard let base, !base.isEmpty else {
            return Self.defaultDrsQuestURL(usingHostFrom: AppConfig.current.drsBaseURL)
        }
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Full prefix in config: .../drs → append /quest
        if trimmed.lowercased().contains("/drs") {
            return URL(string: trimmed + "/quest") ?? Self.defaultDrsQuestURL(usingHostFrom: AppConfig.current.drsBaseURL)
        }
        // Host only, e.g. https://qa-drs-service.doceree.com
        return Self.defaultDrsQuestURL(usingHostFrom: URL(string: trimmed) ?? AppConfig.current.drsBaseURL)
    }

    private static func defaultDrsQuestURL(usingHostFrom root: URL) -> URL {
        root.appendingPathComponent("drs").appendingPathComponent("quest")
    }
}

enum TVRemoteConfigService {
    private static let userDefaultsKey = "com.doceree.sparkfordooh.tvRemoteConfig.cache"
    static let configURL = URL(string: "https://servedbydoceree.doceree.com/resources/p/spark-dooh/tv-config.json")!

    private static let launchLock = NSLock()
    private static var launchConfigSucceeded = false
    private static var launchWaiters: [CheckedContinuation<Void, Never>] = []

    static func waitUntilLaunchConfigNetworkFinished() async {
        launchLock.lock()
        if launchConfigSucceeded {
            launchLock.unlock()
            return
        }
        launchLock.unlock()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            launchLock.lock()
            if launchConfigSucceeded {
                launchLock.unlock()
                cont.resume()
            } else {
                launchWaiters.append(cont)
                launchLock.unlock()
            }
        }
    }

    private static func signalLaunchConfigSucceeded() {
        launchLock.lock()
        launchConfigSucceeded = true
        let waiters = launchWaiters
        launchWaiters = []
        launchLock.unlock()
        waiters.forEach { $0.resume() }
    }

    private static func persist(entry: TVRemoteConfigEntry, key: String) {
        let p = TVRemoteConfigPersisted(
            activation_base_url: entry.activation_base_url,
            drs_base_url: entry.drs_base_url,
            force_update: entry.force_update,
            config_key: key,
            spark_portal_url: entry.spark_portal_url
        )
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private static func tryFetchAndApplyConfig() async -> Bool {
        var request = URLRequest(url: configURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return false
            }
            let root = try JSONDecoder().decode(TVRemoteConfigRoot.self, from: data)
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            let key: String
            let entry: TVRemoteConfigEntry
            if let v = root.tvos[version] {
                key = version
                entry = v
            } else if let d = root.tvos["default"] {
                key = "default"
                entry = d
            } else {
                return false
            }
            let act = entry.activation_base_url.trimmingCharacters(in: .whitespacesAndNewlines)
            let drs = entry.drs_base_url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !act.isEmpty, !drs.isEmpty else { return false }
            persist(entry: entry, key: key)
            TVRemoteConfigStore.shared.apply(entry: entry, key: key)
            print("📡 TV remote config OK [\(key)] environment=\(TVRemoteConfigStore.shared.environmentLabel)")
            return true
        } catch {
            return false
        }
    }

    static func fetchConfigUntilSuccess() async {
        var delaySeconds: Double = 2
        let maxDelay: Double = 45
        var attempt = 0
        while true {
            attempt += 1
            if await tryFetchAndApplyConfig() {
                signalLaunchConfigSucceeded()
                return
            }
            print("⚠️ TV remote config attempt \(attempt) failed — retrying in \(Int(delaySeconds))s…")
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            delaySeconds = min(delaySeconds * 1.35, maxDelay)
        }
    }
}
