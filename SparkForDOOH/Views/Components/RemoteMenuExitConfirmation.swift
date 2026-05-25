//
//  RemoteMenuExitConfirmation.swift
//  SparkForDOOH
//
//  tvOS: Apple TV Remote **Menu** (often used as back/exit) shows a confirmation before terminating the app.
//

import Darwin
import SwiftUI

private enum ExitConfirmFocus: Hashable {
    case stay
    case exit
}

private struct RemoteMenuExitConfirmationOverlay: View {
    @Binding var isPresented: Bool
    @FocusState private var focusedButton: ExitConfirmFocus?
    @Namespace private var focusScope

    private static let message =
        "You’re about to exit Spark for DOOH, which will interrupt the active Care Moments on your screens. Keep the app open to continue sharing valuable clinical content seamlessly."

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 36) {
                Text("Pause Care Moments?")
                    .font(.system(size: 38, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(Self.message)
                    .font(.system(size: 29, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .lineLimit(3)
                    .frame(maxWidth: 1180)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 48) {
                    Button("Stay") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                    .focused($focusedButton, equals: .stay)
                    .prefersDefaultFocus(true, in: focusScope)

                    Button("Exit") {
                        exit(0)
                    }
                    .buttonStyle(.bordered)
                    .focused($focusedButton, equals: .exit)
                }
                .font(.system(size: 29, weight: .medium))
                .focusScope(focusScope)
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 52)
            .frame(minWidth: 920, maxWidth: 1320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .focusSection()
        .onMoveCommand { direction in
            switch direction {
            case .left:
                focusedButton = .stay
            case .right:
                focusedButton = .exit
            default:
                break
            }
        }
        .onAppear {
            focusedButton = .stay
        }
    }
}

private struct RemoteMenuExitConfirmationModifier: ViewModifier {
    @State private var showConfirm = false

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(showConfirm)

            if showConfirm {
                RemoteMenuExitConfirmationOverlay(isPresented: $showConfirm)
            }
        }
        .onExitCommand {
            showConfirm.toggle()
        }
    }
}

extension View {
    /// Presents a confirmation when the user presses the remote **Menu** button (`onExitCommand`).
    func remoteMenuExitConfirmation() -> some View {
        modifier(RemoteMenuExitConfirmationModifier())
    }
}
