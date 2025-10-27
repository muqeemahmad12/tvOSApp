//
//  CarouselSectionView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 07/10/25.
//

import SwiftUI

struct CarouselSectionView: View {
    let title: String
    let movies: [Movie]

    // Non-optional binding for featured carousel; other carousels can pass .constant(0)
    @Binding var featuredIndex: Int

    // Timer only triggers for featured carousel
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 36, weight: .bold))
                .padding(.leading, 80)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 40) {
                        ForEach(movies.indices, id: \.self) { i in
                            NavigationLink(destination: MovieDetailView(movie: movies[i])) {
                                MovieCardView(movie: movies[i])
                                    .id(i)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 80)
                }
                .onReceive(timer) { _ in
                    // Only animate featured carousel
                    if title == "Featured" {
                        withAnimation(.easeInOut(duration: 0.8)) {
                            featuredIndex = (featuredIndex + 1) % movies.count
                            proxy.scrollTo(featuredIndex, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 22)
    }
}
