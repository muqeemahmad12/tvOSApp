//
//  AdListView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import SwiftUI

struct AdListView: View {
    @StateObject private var viewModel = AdListViewModel()

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading ads...")
                } else if let error = viewModel.errorMessage {
                    VStack {
                        Text("❌ \(error)")
                            .foregroundColor(.red)
                        Button("Retry") {
                            viewModel.fetchAds(screenId: "123")
                        }
                        .padding()
                    }
                } else {
                    List(viewModel.ads) { ad in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("🎬 \(ad.assettype.uppercased()) - \(ad.itemspeciality)")
                                .font(.headline)
                            Text("URL: \(ad.itemurl)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                            Text("Sequence: \(ad.sequence)")
                                .font(.caption)
                            Text("Active: \(ad.isActive ? "Yes" : "No")")
                                .font(.caption2)
                                .foregroundColor(ad.isActive ? .green : .red)
                        }
                        .padding(.vertical, 8)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Doceree Ad Items")
            .onAppear {
                if viewModel.ads.isEmpty {
                    viewModel.fetchAds(screenId: "123")
                }
            }
        }
    }
}
