
import SwiftUI
import GoogleInteractiveMediaAds

//struct ContentView: View {
//    @State private var featuredIndex: Int = 0
//    private let featuredMovies = Movie.featuredMovies
//
//    // Top menu focus
//    @FocusState private var isFocusedHome: Bool
//    @FocusState private var isFocusedSearch: Bool
//    @FocusState private var isFocusedSettings: Bool
//
//    var body: some View {
//        NavigationStack {
//            GeometryReader { geo in
//                ZStack {
//                    // Parallax hero background
//                    Image(featuredMovies[featuredIndex].thumbnail)
//                        .resizable()
//                        .scaledToFill()
//                        .frame(width: geo.size.width, height: geo.size.height)
//                        .blur(radius: 60)
//                        .opacity(0.6)
//                        .offset(y: -geo.frame(in: .global).minY * 0.2) // Parallax effect
//                        .edgesIgnoringSafeArea(.all)
//
//                    ScrollView(.vertical, showsIndicators: false) {
//                        VStack(spacing: 40) {
//                            // Top menu
//                            HStack(spacing: 60) {
//                                Button("Home") { print("Home tapped") }
//                                    .buttonStyle(.plain)
//                                    .scaleEffect(isFocusedHome ? 1.1 : 1.0)
//                                    .focused($isFocusedHome)
//                                Button("Search") { print("Search tapped") }
//                                    .buttonStyle(.plain)
//                                    .scaleEffect(isFocusedSearch ? 1.1 : 1.0)
//                                    .focused($isFocusedSearch)
//                                Button("Settings") { print("Settings tapped") }
//                                    .buttonStyle(.plain)
//                                    .scaleEffect(isFocusedSettings ? 1.1 : 1.0)
//                                    .focused($isFocusedSettings)
//                            }
//                            .padding(.leading, 80)
//                            .font(.title2)
//                            .animation(.easeInOut(duration: 0.2), value: isFocusedHome)
//                            .animation(.easeInOut(duration: 0.2), value: isFocusedSearch)
//                            .animation(.easeInOut(duration: 0.2), value: isFocusedSettings)
//
//                            // App Title
//                            Text("TVShowBrowser")
//                                .font(.system(size: 66, weight: .black))
//                                .padding(.leading, 80)
//
//                            // Featured carousel
//                            GeometryReader { featuredGeo in
//                                CarouselSectionView(
//                                    title: "Featured",
//                                    movies: featuredMovies,
//                                    featuredIndex: $featuredIndex
//                                )
//                                .scaleEffect(computeScale(geo: featuredGeo, parentGeo: geo))
//                            }
//                            .frame(height: 300)
//
//                            // Other sections
//                            ForEach(Movie.sampleSections.dropFirst(), id: \.title) { section in
//                                GeometryReader { sectionGeo in
//                                    CarouselSectionView(
//                                        title: section.title,
//                                        movies: section.movies,
//                                        featuredIndex: .constant(0)
//                                    )
//                                    .scaleEffect(computeScale(geo: sectionGeo, parentGeo: geo))
//                                }
//                                .frame(height: 300)
//                            }
//
//                            Spacer(minLength: 160)
//                        }
//                    }
//                }
//            }
//        }
//    }
//
//    // Compute scale based on vertical position (focused section pops slightly)
//    private func computeScale(geo: GeometryProxy, parentGeo: GeometryProxy) -> CGFloat {
//        let midY = geo.frame(in: .global).midY
//        let parentMidY = parentGeo.size.height / 2
//        let distance = abs(parentMidY - midY)
//        let maxDistance: CGFloat = 400 // adjust how fast scaling drops off
//        let minScale: CGFloat = 0.95
//        let maxScale: CGFloat = 1.05
//        let scale = max(minScale, maxScale - (distance / maxDistance) * 0.1)
//        return scale
//    }
//}


import SwiftUI

struct ContentView: View {
    @State private var heroAds: [AdItem] = []
    @State private var adRows: [[AdItem]] = []

    var body: some View {
        if #available(tvOS 16.0, *) {
            NavigationStack {
                VStack(spacing: 40) {
                    if !heroAds.isEmpty {
                        AdDetailSliderView(ads: heroAds, startIndex: 0)
                            .frame(height: 300)
                    }
                    
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 40) {
                            ForEach(adRows.indices, id: \.self) { rowIndex in
                                HStack(spacing: 20) {
                                    ForEach(adRows[rowIndex].indices, id: \.self) { index in
                                        let ad = adRows[rowIndex][index]
                                        NavigationLink(value: ad) {
                                            AdContentView(ad: ad.adType)
//                                                .frame(width: 1280, height: 720)
                                                .cornerRadius(12)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationDestination(for: AdItem.self) { ad in
                    AdDetailSliderView(ads: [ad], startIndex: 0)
                }
                .background(Color.black.ignoresSafeArea())
                .onAppear(perform: loadAds)
            }
        } else {
            // Fallback on earlier versions
        }
    }

    private func loadAds() {
        // Sample mock data for testing
        heroAds = [
//            AdItem(type: "image", url: "https://picsum.photos/800/400", name: nil, duration: 4),
//            AdItem(type: "video", url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4", name: nil, duration: 6)
        ]

        adRows = [
//            [
//                AdItem(type: "image", url: "https://picsum.photos/400/200", name: nil, duration: 5),
//                AdItem(type: "lottie", url: nil, name: "animation1", duration: 5)
//            ],
            [
//                AdItem(type: "video", url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4", name: nil, duration: 7),
                AdItem(type: "vast", url: "https://pubads.g.doubleclick.net/gampad/ads?sz=640x480&iu=/124319096/external/single_ad_samples&ciu_szs=300x250&impl=s&gdfp_req=1&env=vp&output=vast&unviewed_position_start=1", name: nil, duration: 7)
            ]
        ]
    }
}
