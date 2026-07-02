//
//  QRGenerator.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo on 11/7/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import Foundation
import UIKit
import CoreImage.CIFilterBuiltins

// swiftlint:disable:next type_name
public final class QR {
    
	public static func generate(_ string: String) -> UIImage? {
		guard let outputImage: CGImage = self.generate(string) else { return nil }
		
		return UIImage(cgImage: outputImage)
	}
	
	@MainActor
	public static func generate(_ string: String, onView: UIImageView) {
		guard let image: CGImage = self.generate(string) else { return }

		// A zero-sized view cannot back a bitmap context: `CGContext(width:0,height:0,...)` returns
		// nil and we would bail out anyway. Guard explicitly so the degenerate case is intentional
		// and documented, rather than relying on the context creation failing downstream.
		guard onView.frame.size.width > 0, onView.frame.size.height > 0 else { return }

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: Int(onView.frame.size.width),
            height: Int(onView.frame.size.height),
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue) else { return }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: onView.frame.size))
        if let cgImage = context.makeImage() {
            onView.image = UIImage(cgImage: cgImage)
        }
	}
	
	// MARK: - Private Helpers
	
	fileprivate static func generate(_ string: String) -> CGImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        guard let outputImage = filter.outputImage?.transformed(by: transform),
              let cgimg = context.createCGImage(outputImage, from: outputImage.extent) else {
                return nil
        }
        return cgimg
	}
}
