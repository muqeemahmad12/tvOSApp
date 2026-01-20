//
//  ActivationScreenView.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 24/11/25.
//

import SwiftUI
import UIKit

struct ActivationView: View {
    /// Called when activation is considered complete (e.g. backend marks device as ACTIVE).
    var onActivated: () -> Void = {}

    @StateObject private var vm = ActivationViewModel()

    var body: some View {
        ZStack {
            Image("registration_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .overlay(Color.white.opacity(0.0)) // keep original brightness, ensures no empty space
            
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                
                HStack(alignment: .top, spacing: 60) {
                    ActivationCodeSection(
                        activationCode: vm.activationCode,
                        qrURL: vm.qrURL,
                        timeRemaining: vm.timeRemaining,
                        isRefreshing: vm.isCodeExpired
                    )
                    ActivationInstructionsSection()
                        .padding(.top, 20)
                    Spacer()
                }
                .padding(.horizontal, 60)
                
                Spacer(minLength: 40)
                
                ActivationFooter()
                    .padding(.bottom, 30)
            }
        }
        .onAppear {
            // Prevent screensaver/sleep while waiting for activation
            UIApplication.shared.isIdleTimerDisabled = true
            print("🔒 Idle timer disabled during activation")
            
            vm.activateDevice()
        }
        .onChange(of: vm.isActivated) { activated in
            if activated {
                print("✅ Device activated - transitioning to player")
                onActivated()
            }
        }
    }
}

// MARK: - Subviews

private struct ActivationCodeSection: View {
    let activationCode: String
    let qrURL: String
    let timeRemaining: Int
    let isRefreshing: Bool

    var body: some View {
        ZStack {
            // Card background
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.clear)
                .overlay(
                    Image("activation_code_bg")
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                )
            
            VStack(spacing: 32) {
                Text("Activate your TV screen")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 16)
                
                ZStack {
                    QRCodeView(text: qrURL, showBackground: false)
                        .frame(width: 320, height: 320)
                        .opacity(isRefreshing ? 0.3 : 1.0)
                        .padding(.vertical, 8)
                    
                    if isRefreshing {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.6)
                                .progressViewStyle(CircularProgressViewStyle(tint: Color.white))
                            
                            Text("Refreshing code...")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
                
                // Activation code boxes
                HStack(spacing: 16) {
                    ForEach(Array(activationCode.enumerated()), id: \.offset) { _, char in
                        Text(String(char))
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundColor(.black.opacity(0.75))
                            .frame(width: 72, height: 72)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.black.opacity(0.35), lineWidth: 3)
                            )
                    }
                }
                .padding(.bottom, 20)
                
                // Countdown timer (visible when not refreshing)
                if !isRefreshing {
                    Text("Code expires in \(formatTime(timeRemaining))")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(timeRemaining < 60 ? .red : Color.black.opacity(0.6))
                        .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, 36)
        }
        .frame(width: 820, height: 650)
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

private struct ActivationInstructionsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 5) {
                Text("QR Method:")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(Color(hex: "#138bcc"))

                Group {
                    bullet("Open your phone’s camera app")
                    bullet("Log-in to website using credentials provided by vendor")
                    bullet("Choose the hospital / clinic where TV is installed")
                    bullet("Select correct TV screen from list by matching Department & Location")
                }
                .font(.system(size: 26))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .foregroundColor(Color(hex: "#505050"))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Code Method:")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(Color(hex: "#138bcc"))

                Group {
                    bullet("Goto https://spark.doceree.com")
                    bullet("Login using credentials provided by vendor")
                    bullet("Choose the hospital / clinic where TV is installed")
                    bullet("Select correct TV screen from list by matching Department & Location")
                    bullet("Enter the 6 digit code shown on this screen")
                }
                .font(.system(size: 26))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .foregroundColor(Color(hex: "#505050"))
            }
        }
        .frame(minWidth: 520, maxWidth: 640, alignment: .leading)
    }
    
    // Keep bullets aligned across wrapped lines
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: 26, weight: .bold))
            Text(text)
                .font(.system(size: 26))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ActivationFooter: View {
    var body: some View {
        Text("Note: This app is developed for healthcare organizations and their trusted vendor partners, this application provides centralized control of content displayed on facility TVs. For authorized use only.")
            .font(.system(size: 18))
            .foregroundColor(Color(hex: "#505050"))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 60)
            .padding(.bottom, 0)
    }
}


