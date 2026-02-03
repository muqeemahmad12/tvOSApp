//
//  QRCodeView.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 24/11/25.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let text: String
    var showBackground: Bool = false
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        Group {
            if showBackground {
                ZStack {
                    // Background for the activation code
                    Image("activation_code_bg")
                        .resizable()
                        .scaledToFit()
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    
                    qrImageView
                        .padding(32)
                }
            } else {
                qrImageView
            }
        }
    }
    
    private var qrImageView: some View {
        Group {
        if let image = generateQRCode(from: text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Color.red
            }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        if let outputImage = filter.outputImage {
            // Apply transparent background (clear) with black foreground
            let colorFilter = CIFilter.falseColor()
            colorFilter.inputImage = outputImage
            colorFilter.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)    // QR modules
            colorFilter.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)    // Background transparent
            
            guard let coloredImage = colorFilter.outputImage else { return nil }
            
            let scaled = coloredImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
            if let cgimg = context.createCGImage(scaled, from: scaled.extent) {
                return UIImage(cgImage: cgimg)
            }
        }
        return nil
    }
}
