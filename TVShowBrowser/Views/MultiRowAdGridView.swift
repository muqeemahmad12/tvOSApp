//
//  MultiRowAdGridView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import SwiftUI

struct MultiRowAdGridView: View {
    let rows: [AdRow]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 40) {
                ForEach(rows) { row in
                    VStack(alignment: .leading) {
                        Text(row.title)
                            .foregroundColor(.white)
                            .font(.title2)
                            .padding(.leading, 40)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 20) {
                                ForEach(Array(row.ads.enumerated()), id: \.offset) { index, ad in
                                    if #available(tvOS 16.0, *) {
                                        AdGridItemView(ad: ad.adType, isFocused: .constant(false))
                                            .onTapGesture {
                                                // TODO: Trigger click API here
                                                print("Clicked ad in row: \(row.title), index: \(index)")
                                            }
                                    } else {
                                        // Fallback on earlier versions
                                    }
                                }
                            }
                            .padding(.horizontal, 40)
                        }
                        .frame(height: 220)
                    }
                }
            }
            .padding(.vertical, 40)
        }
    }
}
