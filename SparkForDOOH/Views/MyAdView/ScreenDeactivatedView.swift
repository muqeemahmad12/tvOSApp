//
//  ScreenDeactivatedView.swift
//  SparkForDOOH
//
//  Shown when heartbeat reports INACTIVE.
//  Credentials + cache kept; wait for ACTIVE to resume.
//

import SwiftUI

struct ScreenDeactivatedView: View {
    var body: some View {
        ZStack {
            Image("registration_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            GeometryReader { geo in
                let isWide = geo.size.width > geo.size.height
                let illustrationSide = min(geo.size.height * 0.52, geo.size.width * 0.32)
                let textMaxWidth = min(geo.size.width * 0.48, 900)

                HStack(alignment: .center, spacing: isWide ? 48 : 24) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Screen Inactivated")
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundColor(Color(red: 0.0, green: 0.45, blue: 0.91))

                        Text("This screen is disabled in the system and is not eligible to receive content.")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundColor(Color(red: 0.32, green: 0.36, blue: 0.41))
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Please contact your Facility Manager/Administrator to re-enable this screen. Once re-activated and synced, content will resume automatically.")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundColor(Color(red: 0.32, green: 0.36, blue: 0.41))
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 48)
                    }
                    .frame(maxWidth: textMaxWidth, alignment: .leading)
                    .padding(.leading, 60)

                    Spacer(minLength: 24)

                    Image("screen_inactivated")
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: illustrationSide, height: illustrationSide)
                        .padding(.trailing, 80)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .onAppear {
            SentryService.shared.track(SentryAnalyticsEvent.errorScreenActivationFailed, attributes: ["kind": "deactivated"])
            SentryService.shared.breadcrumb(category: "error_ui", message: "screen_deactivated_visible", data: [:])
        }
    }
}

#Preview {
    ScreenDeactivatedView()
}
