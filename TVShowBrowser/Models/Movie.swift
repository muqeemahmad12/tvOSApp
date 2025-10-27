//
//  Movie.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 07/10/25.
//

import Foundation

import Foundation

struct Movie: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let description: String
    let thumbnail: String
}

extension Movie {
    static let featuredMovies: [Movie] = [
        Movie(title: "Inception",    description: "A thief who steals secrets through dreams.", thumbnail: "poster1"),
        Movie(title: "Interstellar", description: "Exploring space and time to save humanity.", thumbnail: "poster2"),
        Movie(title: "Tenet",        description: "Time inversion and espionage thriller.", thumbnail: "poster3")
    ]

    static let popularMovies: [Movie] = [
        Movie(title: "The Matrix", description: "A hacker discovers reality is simulated.", thumbnail: "poster2"),
        Movie(title: "Arrival",    description: "Linguist tries to communicate with aliens.", thumbnail: "poster3"),
        Movie(title: "Gravity",    description: "Survival in low Earth orbit.", thumbnail: "poster1")
    ]

    static let newReleases: [Movie] = [
        Movie(title: "New Sci-Fi 1", description: "Fresh sci-fi release.", thumbnail: "poster3"),
        Movie(title: "New Drama 2",  description: "Compelling drama.", thumbnail: "poster1"),
        Movie(title: "New Thriller", description: "Edge-of-your-seat thriller.", thumbnail: "poster2")
    ]

    static let sampleSections: [(title: String, movies: [Movie])] = [
        (title: "Featured",     movies: featuredMovies),
        (title: "Popular",      movies: popularMovies),
        (title: "New Releases", movies: newReleases)
    ]
}
