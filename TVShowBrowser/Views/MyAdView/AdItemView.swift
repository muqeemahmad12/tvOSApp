//
//  AdItemView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import SwiftUI
import AVKit

struct AdItemView: View {
    let ad: AdItemModel
    
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            if isVideo {
                if let url = URL(string: ad.itemurl) {
                    VideoPlayer(player: player)
                        .onAppear {
                            player = AVPlayer(url: url)
                            player?.play()
                        }
                        .onDisappear {
                            player?.pause()
                        }
                        .frame(height: 220)
                        .cornerRadius(12)
                } else {
                    Text("Invalid Video URL")
                        .foregroundColor(.red)
                }
            } else if isImage {
                AsyncImage(url: URL(string: ad.itemurl)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                    case .failure:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(height: 220)
            } else {
                Text("Unsupported media type: \(ad.assettype)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 6)
    }
    
    private var isVideo: Bool {
        ad.assettype.lowercased() == "video" || ad.itemurl.lowercased().hasSuffix(".mp4")
    }
    
    private var isImage: Bool {
        ad.assettype.lowercased() == "image" ||
        ad.itemurl.lowercased().hasSuffix(".jpg") ||
        ad.itemurl.lowercased().hasSuffix(".png") ||
        ad.itemurl.lowercased().hasSuffix(".gif")
    }
}
