//
//  NetworkMonitor.swift
//  SparkForDOOH
//
//  Monitors network connectivity and publishes status changes.
//

import Foundation
import Network

/// Monitors network connectivity status using NWPathMonitor.
/// Publishes connection state for UI to display appropriate indicators.
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published var isConnected: Bool = true
    @Published var connectionType: ConnectionType = .unknown
    
    // General monitor plus Wi-Fi specific to catch cold-start -> Wi-Fi transitions.
    private let primaryMonitor = NWPathMonitor()
    private let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let queue = DispatchQueue(label: "com.doceree.sparkfordooh.networkmonitor")
    // Multiple TCP targets to reduce single-host block risk.
    private let tcpTargets: [(host: NWEndpoint.Host, port: NWEndpoint.Port)] = [
        (host: "1.1.1.1", port: 80),
        (host: "8.8.8.8", port: 80),
        (host: "208.67.222.222", port: 80)
    ]
    private var periodicProbeTask: Task<Void, Never>?
    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown
    }
    
    private init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        let handler: (String) -> (NWPath) -> Void = { [weak self] reasonPrefix in
            return { path in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    let connected = path.status == .satisfied
                    if connected {
                        self.applyStatus(connected: true, path: path, reason: "\(reasonPrefix)NWPath")
                    } else {
                        self.singleProbe(path: path, reason: "\(reasonPrefix)NWPathUnsatisfiedProbe")
                    }
                }
            }
        }
        primaryMonitor.pathUpdateHandler = handler("Primary")
        wifiMonitor.pathUpdateHandler = handler("WiFi")
        
        primaryMonitor.start(queue: queue)
        wifiMonitor.start(queue: queue)
        
        // Evaluate the current path immediately so cold starts reflect reality.
        evaluateCurrentPath(reason: "InitialPath")
    }

    /// Manually refresh connectivity (useful when returning to foreground).
    func refreshConnectivity() {
        evaluateCurrentPath(reason: "ManualRefresh")
    }
    
    private func singleProbe(path: NWPath, reason: String) {
        Task.detached { [weak self] in
            guard let self = self else { return }
            let success = await self.performProbe()
            await MainActor.run {
                print("🛰️ Probe result: \(success ? "online" : "offline") [\(reason)]")
                self.applyStatus(connected: success, path: path, reason: success ? reason : "\(reason)Failed")
            }
        }
    }

    private func startPeriodicProbe() {
        guard periodicProbeTask == nil else { return }
        periodicProbeTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let success = await self.performProbe()
                await MainActor.run {
                    print("🔁 Periodic probe: \(success ? "online" : "offline")")
                    self.applyStatus(connected: success, path: self.primaryMonitor.currentPath, reason: success ? "PeriodicProbe" : "PeriodicProbeFailed")
                }
                // If we just confirmed online, back off longer.
                try? await Task.sleep(nanoseconds: success ? 12_000_000_000 : 6_000_000_000)
            }
        }
    }
    
    private func stopPeriodicProbe() {
        periodicProbeTask?.cancel()
        periodicProbeTask = nil
    }
    
    private func performProbe() async -> Bool {
        // Quick TCP reachability first across multiple targets to avoid slow HTTP timeouts on blocked hosts.
        for (host, port) in tcpTargets {
            let tcpQueue = DispatchQueue(label: "com.doceree.sparkfordooh.tcpprobe.\(host)")
            let tcpSucceeded: Bool = await withCheckedContinuation { continuation in
                var resumed = false
                let resume: (Bool) -> Void = { value in
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: value)
                }
                let connection = NWConnection(host: host, port: port, using: .tcp)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        print("🛰️ TCP probe succeeded (\(host):\(port))")
                        connection.cancel()
                        resume(true)
                    case .failed, .cancelled:
                        resume(false)
                    default:
                        break
                    }
                }
                connection.start(queue: tcpQueue)
                tcpQueue.asyncAfter(deadline: .now() + 3) { // allow Wi-Fi to finish associating
                    resume(false)
                    connection.cancel()
                }
            }
            if tcpSucceeded { return true }
        }
        
        return false
    }
    
    /// Allow other services (e.g., successful API calls) to force mark online.
    func markOnline(reason: String = "ManualOnline") {
        let path = primaryMonitor.currentPath
        DispatchQueue.main.async {
            self.applyStatus(connected: true, path: path, reason: reason)
        }
    }

    private func evaluateCurrentPath(reason: String) {
        let path = primaryMonitor.currentPath
        DispatchQueue.main.async {
            let connected = path.status == .satisfied
            if connected {
                self.applyStatus(connected: true, path: path, reason: reason)
            } else {
                self.singleProbe(path: path, reason: "\(reason)Probe")
            }
        }
    }

    private func applyStatus(connected: Bool, path: NWPath, reason: String) {
        let inferredType = getConnectionType(path, fallback: connected ? .wifi : .unknown)
        print("🛰️ Path status: \(path.status) | expensive=\(path.isExpensive) constrained=\(path.isConstrained) [\(reason)], inferredType=\(inferredType)")
        let wasConnected = isConnected
        isConnected = connected
        connectionType = inferredType

        if connected != wasConnected {
            let reasonTag = String(reason.prefix(200))
            if !connected {
                SentryService.shared.track(
                    SentryAnalyticsEvent.networkConnectivityLost,
                    attributes: ["reason": reasonTag]
                )
                SentryService.shared.breadcrumb(category: "network", message: "connectivity_lost", data: ["reason": reasonTag])
            } else {
                SentryService.shared.track(
                    SentryAnalyticsEvent.networkConnectivityRestored,
                    attributes: ["reason": reasonTag]
                )
                SentryService.shared.breadcrumb(category: "network", message: "connectivity_restored", data: ["reason": reasonTag])
            }
        }
        if connected {
            stopPeriodicProbe()
            print("🌐 Network: Connected (\(connectionType)) [\(reason)]")
        } else {
            startPeriodicProbe()
            print("📵 Network: Disconnected [\(reason), status=\(path.status)]")
        }
    }
    
    private func getConnectionType(_ path: NWPath, fallback: ConnectionType = .unknown) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        }
        return fallback
    }
}

