//
//  DebugScreenStatusOverlay.swift
//  SparkForDOOH
//
//  DEBUG-only controls to manually toggle Deactivate / Inactivate / ACTIVE for local testing.
//  tvOS: use remote Play/Pause to toggle Deactivate ↔ ACTIVE, or focus the buttons.
//

#if DEBUG
import SwiftUI

/// Floating DEBUG controls. Prefer **Play/Pause** on the Siri Remote to toggle
/// Deactivate ↔ ACTIVE — on-screen buttons are also focusable when the remote can reach them.
struct DebugScreenStatusOverlay: View {
    @FocusState private var focused: DebugFocus?
    @Namespace private var focusScope

    private enum DebugFocus: Hashable {
        case deactivate
        case inactivate
        case active
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("DEBUG · Play/Pause toggles Deactivate ↔ ACTIVE")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button {
                    HeartbeatAPI.shared.debugForceDeactivate()
                } label: {
                    Text("Force Deactivate")
                        .frame(minWidth: 180, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.85))
                .focused($focused, equals: .deactivate)
                .prefersDefaultFocus(true, in: focusScope)

                Button {
                    HeartbeatAPI.shared.debugForceInactivate()
                } label: {
                    Text("Force Inactivate")
                        .frame(minWidth: 180, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange.opacity(0.9))
                .focused($focused, equals: .inactivate)

                Button {
                    HeartbeatAPI.shared.debugForceActive()
                } label: {
                    Text("Force ACTIVE")
                        .frame(minWidth: 180, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green.opacity(0.85))
                .focused($focused, equals: .active)
            }
            .focusScope(focusScope)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .focusSection()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 48)
        .padding(.trailing, 48)
        .onAppear {
            // Delay so we win focus after player / exit-catcher settle.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                focused = .deactivate
            }
        }
        .onPlayPauseCommand {
            toggleViaPlayPause()
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                switch focused {
                case .active: focused = .inactivate
                case .inactivate: focused = .deactivate
                default: focused = .deactivate
                }
            case .right:
                switch focused {
                case .deactivate: focused = .inactivate
                case .inactivate: focused = .active
                default: focused = .active
                }
            default: break
            }
        }
    }

    private func toggleViaPlayPause() {
        if HeartbeatAPI.shared.isAwaitingActiveStatus {
            print("🧪 DEBUG Play/Pause → Force ACTIVE")
            HeartbeatAPI.shared.debugForceActive()
        } else {
            print("🧪 DEBUG Play/Pause → Force Deactivate")
            HeartbeatAPI.shared.debugForceDeactivate()
        }
    }
}
#endif
