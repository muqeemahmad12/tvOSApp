//
//  ActivationFailedView.swift
//  SparkForDOOH
//
//  Full-screen view when poll API returns INACTIVE. Matches WaitingForContentView / ConnectionLostView layout.
//

import SwiftUI

struct ActivationFailedView: View {
    var body: some View {
        ZStack {
            Image("registration_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            HStack(alignment: .center, spacing: 32) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Activation Failed")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundColor(Color(red: 0.0, green: 0.45, blue: 0.91))

                    Text("Restart the application to generate a new QR code and try the activation again.")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundColor(Color(red: 0.32, green: 0.36, blue: 0.41))
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 520, alignment: .leading)

                    Text("We couldn't link this screen to your facility. Please check your internet connection and verify the pairing code/QR scan on the web dashboard.")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundColor(Color(red: 0.32, green: 0.36, blue: 0.41))
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 640, alignment: .leading)
                        .padding(.top, 62)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 60)
                .padding(.top, -60)

                Spacer()

                Image("activation_failed")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 550, maxHeight: 466)
                    .padding(.trailing, 80)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

#Preview {
    ActivationFailedView()
}
