//
//  AppRootViewModel.swift
//  SparkForDOOH
//
//  Created by Cursor on 03/12/25.
//

import Foundation

/// High-level app phases for this kiosk-style tvOS app.
@MainActor
final class AppRootViewModel: ObservableObject {
    enum Phase {
        case activating
        case playing
    }

    @Published var phase: Phase = .activating
}


