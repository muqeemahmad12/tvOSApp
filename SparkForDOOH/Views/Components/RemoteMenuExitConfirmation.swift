//
//  RemoteMenuExitConfirmation.swift
//  SparkForDOOH
//
//  tvOS: Apple TV Remote **Menu** (back/exit) shows a confirmation before terminating the app.
//  Uses UIKit press interception because SwiftUI `onExitCommand` often never fires while
//  playback / non-focusable screens have no focusable target (or VideoPlayer steals Menu).
//

import Darwin
import SwiftUI
import UIKit

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

// MARK: - UIKit Menu press catcher (reliable on player / waiting screens)

private final class MenuPressGestureRecognizer: UIGestureRecognizer {
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        if presses.contains(where: { $0.type == .menu }) {
            state = .began
            state = .ended
            return
        }
        state = .failed
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        // Handled in began
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        state = .failed
    }
}

/// Transparent host that installs a window-level Menu press recognizer.
private struct MenuPressCatcher: UIViewRepresentable {
    var onMenu: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMenu: onMenu)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onMenu = onMenu
        context.coordinator.attach(to: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onMenu: () -> Void
        private weak var hostView: UIView?
        private var recognizer: MenuPressGestureRecognizer?
        private var attachedWindow: UIWindow?

        init(onMenu: @escaping () -> Void) {
            self.onMenu = onMenu
        }

        func attach(to view: UIView) {
            hostView = view
            // Defer until the view is in a window.
            DispatchQueue.main.async { [weak self] in
                self?.installIfNeeded()
            }
        }

        private func installIfNeeded() {
            guard let hostView, let window = hostView.window else { return }
            if attachedWindow === window, recognizer != nil { return }

            detach()
            let recognizer = MenuPressGestureRecognizer(target: self, action: #selector(menuPressed))
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            recognizer.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
            self.attachedWindow = window
            print("📺 Menu exit catcher installed on window")
        }

        func detach() {
            if let recognizer, let window = attachedWindow {
                window.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            attachedWindow = nil
        }

        @objc private func menuPressed() {
            onMenu()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private struct RemoteMenuExitConfirmationModifier: ViewModifier {
    @State private var showConfirm = false

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(showConfirm)
                // Keep a focusable target so SwiftUI `onExitCommand` can fire when UIKit path misses.
                .background(
                    Button("") { }
                        .opacity(0.01)
                        .accessibilityHidden(true)
                )

            if showConfirm {
                RemoteMenuExitConfirmationOverlay(isPresented: $showConfirm)
            }

            MenuPressCatcher {
                handleMenuPress()
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        .onExitCommand {
            handleMenuPress()
        }
    }

    private func handleMenuPress() {
        showConfirm.toggle()
        print(showConfirm ? "📺 Exit confirmation shown (Menu)" : "📺 Exit confirmation dismissed (Menu)")
    }
}

extension View {
    /// Presents a confirmation when the user presses the remote **Menu** button.
    func remoteMenuExitConfirmation() -> some View {
        modifier(RemoteMenuExitConfirmationModifier())
    }
}
