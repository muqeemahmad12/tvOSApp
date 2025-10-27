import SwiftUI

struct MovieRowView: View {
    let movie: Movie
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(movie.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 360, height: 205)
                .cornerRadius(12)
                .scaleEffect(isFocused ? 1.08 : 1.0)
                .shadow(color: .black.opacity(isFocused ? 0.35 : 0.15), radius: isFocused ? 20 : 6, x: 0, y: 6)
                .animation(.easeInOut(duration: 0.18), value: isFocused)

            Text(movie.title)
                .foregroundColor(.primary)
                .font(.headline)
        }
        .focused($isFocused)
    }
}
