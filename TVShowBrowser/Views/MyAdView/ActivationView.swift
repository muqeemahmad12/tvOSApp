//
//  ActivationScreenView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 24/11/25.
//

import SwiftUI

struct ActivationView: View {
    @State private var navigate = false
    @StateObject private var listVM = AdListViewModel()
    @StateObject private var vm = ActivationViewModel()

    var body: some View {
        ZStack {
            // Background
            Image("placeholder_image")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 40) {

                // Title
                Text("Activate your TV screen")
                    .font(.system(size: 85, weight: .semibold))
                    .foregroundColor(Color(hex: "#138bcc"))
                    .padding(.top, 50)

                Spacer()
                HStack(alignment: .top, spacing: 80) {

                    // LEFT SIDE — QR + Activation Code
                    VStack(spacing: 40) {

                        // QR Code
                        QRCodeView(text: vm.qrURL)
                            .frame(width: 450, height: 450)
                        Spacer()
                        // Activation Code boxes — NOW MOVED TO LEFT
                        HStack(spacing: 20) {
                            ForEach(Array(vm.activationCode.enumerated()), id: \.offset) { index, char in
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

                    // RIGHT — Instructions
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
                    Spacer()
                }

                // Footer Note
                Text("Note: This app is developed for healthcare organizations and their trusted vendor partners, this application provides centralized control of content displayed on facility TVs. For authorized use only.")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "#505050"))   // your color code
                    .padding(.bottom, 20)
            }
//            .padding(.horizontal, 60)
        }
        .onAppear {
            vm.activateDevice()
            // Auto navigate after 10 seconds
//            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
//                UIApplication.shared.setRootView(
//                    AdPlayerView(listVM: listVM)
//                        .ignoresSafeArea()
//                )
//
//                listVM.fetchAds(screenId: "174", reqNum: 1)
//            }
        }        
    }
}

extension UIApplication {
    func setRootView<Content: View>(_ view: Content) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first else { return }
        
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
    }
}
