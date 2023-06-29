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

open class QR {
    
	open class func generate(_ string: String) -> UIImage? {
		guard let outputImage: CGImage = self.generate(string) else { return nil }
		let image = UIImage(cgImage: outputImage)
		
		return image
	}
	
	open class func generate(_ string: String, onView: UIImageView) {
		guard let image: CGImage = self.generate(string) else { return }
		
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
	
	fileprivate class func generate(_ string: String) -> CGImage? {
        let context = CIContext()
        if #available(iOS 13.0, *) {
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(string.utf8)
            guard let outputImage = filter.outputImage,
                  let cgimg = context.createCGImage(outputImage, from: outputImage.extent) else {
                    return nil
            }
            return cgimg
        } else {
            let stringData = string.data(using: String.Encoding.utf8)
            let filter = CIFilter(name: "CIQRCodeGenerator")
            filter?.setValue(stringData, forKey: "inputMessage")
            filter?.setValue("H", forKey: "inputCorrectionLevel")
            guard let outputImage = filter?.outputImage,
                  let cgimg = context.createCGImage(outputImage, from: outputImage.extent) else {
                    return nil
            }
            return cgimg
        }
	}
}
