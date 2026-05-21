//
//  GIGScannerViewController.swift
//  GiGLibrary
//
//  Created by Judith Medina on 7/5/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import UIKit
import AVFoundation

public protocol GIGScannerDelegate: AnyObject {
	
	func didSuccessfullyScan(_ scannedValue: String, tye: String)
}

open class GIGScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
	
	
	weak var delegate: GIGScannerDelegate?
	fileprivate let session: AVCaptureSession
	fileprivate let device: AVCaptureDevice
	fileprivate let output: AVCaptureMetadataOutput
	fileprivate var preview: AVCaptureVideoPreviewLayer?
	fileprivate var input: AVCaptureDeviceInput?
	
	
	// MARK: - INIT
	
	required public init?(coder aDecoder: NSCoder) {
		
		self.session = AVCaptureSession()
		guard let device = AVCaptureDevice.default(for: AVMediaType.video) else { return nil }
		self.device = device
		self.output = AVCaptureMetadataOutput()
		
		do {
			self.input = try AVCaptureDeviceInput(device: device)
		} catch {
			// Error handling, if needed
		}
		
		super.init(coder: aDecoder)
	}
	
	deinit {
		// no-op
	}
	
	override open func viewDidLoad() {
		super.viewDidLoad()
		self.setupScannerWithProperties()
	}
	
	
	// MARK: - PUBLIC
	
	public func isCameraAvailable() -> Bool {
		
		let authCamera = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
		
		switch authCamera {
			
		case AVAuthorizationStatus.authorized:
			return true
			
		case AVAuthorizationStatus.denied:
			return false
			
		case AVAuthorizationStatus.restricted:
			return false
			
		case AVAuthorizationStatus.notDetermined:
			AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { _ in
				//                return true
			})
			return true
		@unknown default:
			AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { _ in
				//                return true
			})
			return true
		}
	}
	
	public func setupScanner(_ metadataObject: [AnyObject]?) {
		guard let metadata = metadataObject as? [AVMetadataObject.ObjectType] else {return}
		self.output.metadataObjectTypes = metadata
		
		if !self.output.availableMetadataObjectTypes.isEmpty {
			self.output.metadataObjectTypes = metadata
		}
	}
	
	public func startScanning() {
		self.session.startRunning()
	}
	
	public func stopScanning() {
		self.session.stopRunning()
	}
	
	public func enableTorch(_ enable: Bool) {
		
		do {
			try self.device.lockForConfiguration()
		} catch {
			return
		}
		
		if self.device.hasTorch {
			
			if enable {
				self.device.torchMode = .on
			} else {
				self.device.torchMode = .off
			}
			
		}
		
		self.device.unlockForConfiguration()
	}
	
	public func focusCamera(_ focusPoint: CGPoint) {
		
		do {
			try self.device.lockForConfiguration()
			self.device.focusPointOfInterest = focusPoint
			self.device.focusMode = AVCaptureDevice.FocusMode.continuousAutoFocus
			self.device.exposurePointOfInterest = focusPoint
			self.device.exposureMode = AVCaptureDevice.ExposureMode.continuousAutoExposure
		} catch let error as NSError {
			LogError(error)
		}
	}
	
	// MARK: - PRIVATE
	
	func setupScannerWithProperties() {

		if let input = self.input, self.session.canAddInput(input) {
			self.session.addInput(input)
		}
		self.session.addOutput(self.output)
		self.output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
		
		self.setupScanner(self.setupOutputWithDefaultValues() as [AnyObject]?)
		self.setupPreviewLayer()
	}
	
	func setupOutputWithDefaultValues() -> [AVMetadataObject.ObjectType] {
		
		return [
			AVMetadataObject.ObjectType.upce,
			AVMetadataObject.ObjectType.code39,
			AVMetadataObject.ObjectType.code39Mod43,
			AVMetadataObject.ObjectType.ean13,
			AVMetadataObject.ObjectType.ean8,
			AVMetadataObject.ObjectType.code93,
			AVMetadataObject.ObjectType.code128,
			AVMetadataObject.ObjectType.pdf417,
			AVMetadataObject.ObjectType.aztec,
			AVMetadataObject.ObjectType.qr
		]
	}
	
	func setupPreviewLayer() {
		let preview = AVCaptureVideoPreviewLayer(session: self.session)
		preview.videoGravity = AVLayerVideoGravity.resizeAspectFill
		preview.frame = self.view.bounds
		self.preview = preview
		self.view.layer.addSublayer(preview)
	}
	
	
	public func metadataOutput(captureOutput: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
		
		for metadata in metadataObjects {
			
			let readableCode = metadata as? AVMetadataMachineReadableCodeObject
			guard   let value = readableCode?.stringValue,
				let type = readableCode?.type
				else {return}
			
			self.delegate?.didSuccessfullyScan(value, tye: type.rawValue)
		}
	}
	
}
