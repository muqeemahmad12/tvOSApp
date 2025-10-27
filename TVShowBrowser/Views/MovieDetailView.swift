import SwiftUI

struct MovieDetailView: View {
    let movie: Movie

    var body: some View {
        VStack(spacing: 28) {
            Image(movie.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 760)
                .cornerRadius(14)
                .shadow(radius: 12)

            Text(movie.title)
                .font(.system(size: 46, weight: .bold))

            Text(movie.description)
                .font(.title3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 900)

            Spacer()

            // simple Play button placeholder
            Button(action: {
                // Future: AVPlayer playback can be triggered here
                print("Play tapped: \(movie.title)")
            }) {
                Text("Play")
                    .font(.headline)
                    .frame(width: 260, height: 64)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.96))  // Theme B: light
        .foregroundColor(.primary)
    }
}
