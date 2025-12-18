//
//  MediaSessionHelper.swift
//  SparkForDOOH
//
//  Configures audio session and suppresses Now Playing UI for DOOH playback.
//

import AVFoundation
import MediaPlayer
import UIKit

/// Manages media session configuration for DOOH playback.
/// - Suppresses Now Playing info panel
/// - Configures audio session for continuous playback
/// - Handles remote control events to prevent accidental pauses
final class MediaSessionHelper {
    static let shared = MediaSessionHelper()
    private init() {}
    
    /// Configure audio session for DOOH playback
    func configureForPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Set category for playback (not recording)
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            
            // Activate the session
            try audioSession.setActive(true)
            
            print("🔊 Audio session configured for DOOH playback")
        } catch {
            print("⚠️ Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    /// Clear Now Playing info to suppress the info panel
    func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        print("🔇 Cleared Now Playing info")
    }
    
    /// Set minimal Now Playing info (optional - can help control what's displayed)
    func setMinimalNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "",
            MPMediaItemPropertyArtist: "",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
    }
    
    /// Begin receiving remote control events
    func beginReceivingRemoteControlEvents() {
        UIApplication.shared.beginReceivingRemoteControlEvents()
        
        // Set up command center to handle (and ignore) remote events
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Disable all remote commands to prevent interaction
        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.togglePlayPauseCommand.isEnabled = false
        commandCenter.stopCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false
        
        print("🎮 Remote control events configured (commands disabled)")
    }
    
    /// Stop receiving remote control events
    func endReceivingRemoteControlEvents() {
        UIApplication.shared.endReceivingRemoteControlEvents()
        print("🎮 Remote control events ended")
    }
    
    /// Full setup for DOOH playback
    func setupForDOOHPlayback() {
        configureForPlayback()
        clearNowPlayingInfo()
        beginReceivingRemoteControlEvents()
    }
    
    /// Cleanup when playback ends
    func cleanup() {
        endReceivingRemoteControlEvents()
        clearNowPlayingInfo()
    }
}

