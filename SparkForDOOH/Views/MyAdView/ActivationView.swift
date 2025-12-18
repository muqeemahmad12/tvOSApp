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
            FullscreenBackground(imageName: "placeholder_image")

            VStack(spacing: 40) {
                ActivationTitle()

                Spacer()
                HStack(alignment: .top, spacing: 80) {
                    ActivationCodeSection(activationCode: vm.activationCode,
                                          qrURL: vm.qrURL)
                    ActivationInstructionsSection()
                    Spacer()
                }

                ActivationFooter()
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

private struct ActivationTitle: View {
    var body: some View {
        Text("Activate your TV screen")
            .font(.system(size: 85, weight: .semibold))
            .foregroundColor(Color(hex: "#138bcc"))
            .padding(.top, 50)
    }
}

private struct ActivationCodeSection: View {
    let activationCode: String
    let qrURL: String

    var body: some View {
        VStack(spacing: 40) {
            QRCodeView(text: qrURL)
                .frame(width: 450, height: 450)
            Spacer()
            HStack(spacing: 20) {
                ForEach(Array(activationCode.enumerated()), id: \.offset) { _, char in
                    Text(String(char))
                        .font(.system(size: 60, weight: .semibold))
                        .foregroundColor(Color(hex: "#505050"))
                        .frame(width: 100, height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.gray.opacity(0.6), lineWidth: 4)
                        )
                }
            }
        }
    }
}

private struct ActivationInstructionsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            VStack(alignment: .leading, spacing: 5) {
                Text("QR Method:")
                    .font(.system(size: 35, weight: .medium))
                    .foregroundColor(Color(hex: "#505050"))

                Group {
                    Text("- Open your phone’s camera app")
                    Text("- Log-in to website using credentials provided by vendor")
                    Text("- Choose the hospital / clinic where TV is installed")
                    Text("- Select correct TV screen from list by matching Department & Location")
                }
                .font(.system(size: 25))
                .foregroundColor(Color(hex: "#505050"))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Code Method:")
                    .font(.system(size: 35, weight: .medium))
                    .foregroundColor(Color(hex: "#505050"))

                Group {
                    Text("- Goto https://spark.doceree.com")
                    Text("- Login using credentials provided by vendor")
                    Text("- Choose the hospital / clinic where TV is installed")
                    Text("- Select correct TV screen from list by matching Department & Location")
                    Text("- Enter the 6 digit code shown on this screen")
                }
                .font(.system(size: 25))
                .foregroundColor(Color(hex: "#505050"))
            }
        }
    }
}

private struct ActivationFooter: View {
    var body: some View {
        Text("Note: This app is developed for healthcare organizations and their trusted vendor partners, this application provides centralized control of content displayed on facility TVs. For authorized use only.")
            .font(.system(size: 18))
            .foregroundColor(Color(hex: "#505050"))
            .padding(.bottom, 20)
    }
}


