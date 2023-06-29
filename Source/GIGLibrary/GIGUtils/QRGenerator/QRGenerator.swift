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
		guard let outputImage: CIImage = self.generate(string) else { return nil }
		let image = UIImage(ciImage: outputImage)
		
		return image
	}
	
	open class func generate(_ string: String, onView: UIImageView) {
		guard let image: CIImage = self.generate(string) else { return }
		
		let scaleX = onView.frame.size.width / image.extent.size.width
		let scaleY = onView.frame.size.height / image.extent.size.height
		
		let transformedImage = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
		
		onView.image = UIImage(ciImage: transformedImage)
	}
    
    open class func create(string: String) -> UIImage {
        if #available(iOS 13.0, *) {
            let context = CIContext()
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(string.utf8)
            guard let outputImage = filter.outputImage,
                  let cgimg = context.createCGImage(outputImage, from: outputImage.extent) else {
                return UIImage()
            }
            return UIImage(cgImage: cgimg)
        }
        
        return UIImage()
    }
	
	// MARK: - Private Helpers
	
	fileprivate class func generate(_ string: String) -> CIImage? {
        if #available(iOS 13.0, *) {
            let context = CIContext()
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(string.utf8)
            guard let outputImage = filter.outputImage,
                  let cgimg = context.createCGImage(outputImage, from: outputImage.extent) else {
                    return nil
            }
            return CIImage(cgImage: cgimg)
        } else {
            let stringData = string.data(using: String.Encoding.utf8)
            let filter = CIFilter(name: "CIQRCodeGenerator")
            filter?.setValue(stringData, forKey: "inputMessage")
            filter?.setValue("H", forKey: "inputCorrectionLevel")
            
            return filter?.outputImage
        }
	}
}
