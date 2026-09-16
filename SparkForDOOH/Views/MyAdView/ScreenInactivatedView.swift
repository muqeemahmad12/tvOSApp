//
//  ScreenInactivatedView.swift
//  SparkForDOOH
//
//  Shown when the screen must re-register / re-login (activation failed / inactivated).
//

import SwiftUI

struct ScreenInactivatedView: View {
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

                        Text("This screen must be re-registered. Restart the application to generate a new QR code and log in again on the web dashboard.")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundColor(Color(red: 0.32, green: 0.36, blue: 0.41))
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("We couldn't keep this screen linked to your facility. Please check your internet connection, then complete pairing again after restart.")
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
            SentryService.shared.track(SentryAnalyticsEvent.errorScreenActivationFailed, attributes: ["kind": "inactivated"])
            SentryService.shared.breadcrumb(category: "error_ui", message: "screen_inactivated_visible", data: [:])
        }
    }
}

#Preview {
    ScreenInactivatedView()
}
