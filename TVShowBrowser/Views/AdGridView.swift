//
//  AdGridView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import SwiftUI

struct AdGridView: View {
    let ads: [UIAdType]
    @State private var focusedIndex: Int? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(Array(ads.enumerated()), id: \.offset) { index, ad in
                    AdGridItemView(ad: ad, isFocused: Binding(
                        get: { focusedIndex == index },
                        set: { if $0 { focusedIndex = index } }
                    ))
                }
            }
            .padding(.horizontal, 40)
        }
        .frame(height: 220)
    }
}
