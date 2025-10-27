//
//  MovieCardView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 07/10/25.
//

import SwiftUI

struct MovieCardView: View {
    let movie: Movie
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(movie.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 360, height: 205)
                .cornerRadius(12)
                .scaleEffect(isFocused ? 1.08 : 1.0)
                .shadow(color: Color.black.opacity(isFocused ? 0.35 : 0.12),
                        radius: isFocused ? 22 : 6, x: 0, y: 8)
                .animation(.easeInOut(duration: 0.18), value: isFocused)

            Text(movie.title)
                .font(.headline)
                .lineLimit(1)
                .frame(width: 360)
        }
        .focused($isFocused)
    }
}
