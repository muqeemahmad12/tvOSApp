//
//  AdPlayerView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import SwiftUI
import AVKit

struct AdPlayerView: View {
    @StateObject private var viewModel = AdPlayerViewModelNew()
    @ObservedObject var listVM: AdListViewModel
    @State private var videoFullScreen = false

    var body: some View {
        ZStack {
            if let group = viewModel.currentGroup {
                GeometryReader { geo in
                    let screenWidth = geo.size.width
                    let screenHeight = geo.size.height
                    let hasImages = group.ii.contains { $0.assettype.lowercased() == "image" }
                    let videoWidth = hasImages ? screenWidth * 0.7 : screenWidth
                    let videoHeight = hasImages ? videoWidth * 9 / 16 : screenHeight
                    let bottomImageHeight = screenHeight - videoHeight
                    let rightImageWidth = screenWidth - videoWidth

                    ZStack(alignment: .topLeading) {
                        // MARK: - Video Player
                        if let _ = group.ii.first(where: { $0.assettype.lowercased() == "video" }) {
                            VideoPlayer(player: viewModel.activePlayer)
                                .aspectRatio(16/9, contentMode: .fit)
                                .frame(width: videoWidth, height: videoHeight)
                                .clipped()
                                .position(x: videoWidth / 2,
                                          y: hasImages ? (videoHeight / 1.1) : screenHeight / 2)
                                .animation(.easeInOut(duration: 1.0), value: hasImages)
                        }

                        // MARK: - Bottom Image
                        if let bottomAd = group.ii.filter({ $0.assettype.lowercased() == "image" }).first {
                            if let img = viewModel.imageCache[bottomAd.itemurl] {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: videoWidth, height: bottomImageHeight)
                                    .clipped()
                                    .position(x: videoWidth / 2,
                                              y: screenHeight - bottomImageHeight / 2)
                            }
                        }

                        // MARK: - Right Vertical Image (20% width)
                        if let rightAd = group.ii.filter({ $0.assettype.lowercased() == "image" }).last {
                            if let img = viewModel.imageCache[rightAd.itemurl] {
                                Image(uiImage: img)
//                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: (screenWidth - videoWidth),
                                           height: screenHeight)
                                    .clipped()
                                    .position(x: videoWidth + (rightImageWidth / 2),
                                              y: screenHeight / 2)
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.8), value: viewModel.slideOffset)
                .offset(x: viewModel.slideOffset)
            } else {
                Text("🎬 Waiting for ads...")
                    .foregroundColor(.gray)
            }
        }
        // MARK: - ViewModel Triggers
        .onChange(of: listVM.groupedAds) { newGroups in
            if !newGroups.isEmpty {
                viewModel.startPlayback(with: newGroups)
            }
        }
        .onAppear {
            if !listVM.groupedAds.isEmpty {
                viewModel.startPlayback(with: listVM.groupedAds)
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}
