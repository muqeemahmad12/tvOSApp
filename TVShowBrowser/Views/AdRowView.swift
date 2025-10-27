//
//  AdRowView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import SwiftUI

struct AdRowView: View {
    let ads: [UIAdType]
    let title: String
    var onAdSelected: ((UIAdType, Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title2)
                .foregroundColor(.white)
                .padding(.leading, 40)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 40) {
                    ForEach(ads.indices, id: \.self) { index in
                        if #available(tvOS 16.0, *) {
                            AdGridItemView(ad: ads[index], isFocused: .constant(false))
                                .onTapGesture {
                                    onAdSelected?(ads[index], index)
                                }
                        } else {
                            // Fallback on earlier versions
                        }
                    }
                }
                .padding(.horizontal, 40)
            }
        }
    }
}
