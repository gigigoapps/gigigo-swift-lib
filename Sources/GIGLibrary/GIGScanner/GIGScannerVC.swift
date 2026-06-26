//
//  GIGScannerVC.swift
//  Orchextra
//
//  Created by Judith Medina on 23/08/2017.
//  Copyright © 2017 Gigigo Mobile Services S.L. All rights reserved.
//

import UIKit
import AVFoundation


public protocol GIGScannerOutput {
	func didSuccessfullyScan(_ scannedValue: String, type: String)
}

public class GIGScannerVC: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
	
	public var scannerOutput: GIGScannerOutput?
	var captureSession: AVCaptureSession?
	var previewLayer: AVCaptureVideoPreviewLayer?
	var codeFrameView: UIView?
	var captureDevice: AVCaptureDevice?
	
	override public func viewDidLoad() {
		super.viewDidLoad()
		guard let captureDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
			LogWarn("No video capture device available")
			return
		}

		do {
			let input = try AVCaptureDeviceInput(device: captureDevice)
			self.captureSession = AVCaptureSession()
			self.captureSession?.addInput(input)
			
			let captureMetadataOutput = AVCaptureMetadataOutput()
			self.captureSession?.addOutput(captureMetadataOutput)
			
			captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
			captureMetadataOutput.metadataObjectTypes = [
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
			
			self.addPreviewLayer()
			self.captureDevice = captureDevice

		} catch {
			LogWarn("Error initialize camera")
			return
		}
	}
	
	// MARK: - PUBLIC
	
	public func startScanning() {
		self.captureSession?.startRunning()
	}
	
	public func stopScanning() {
		self.captureSession?.stopRunning()
	}
	
	public func enableTorch(_ enable: Bool) {
		guard let captureDevice = self.captureDevice else { return }

		do {
			try captureDevice.lockForConfiguration()
			defer { captureDevice.unlockForConfiguration() }
			if captureDevice.hasTorch {
				captureDevice.torchMode = enable ? .on : .off
			}
		} catch let error as NSError {
			LogError(error)
		}
	}
	
	public func focusCamera(_ focusPoint: CGPoint) {
		guard let captureDevice = self.captureDevice else { return }

		do {
			try captureDevice.lockForConfiguration()
			defer { captureDevice.unlockForConfiguration() }
			captureDevice.focusPointOfInterest = focusPoint
			captureDevice.focusMode = AVCaptureDevice.FocusMode.continuousAutoFocus
			captureDevice.exposurePointOfInterest = focusPoint
			captureDevice.exposureMode = AVCaptureDevice.ExposureMode.continuousAutoExposure
		} catch let error as NSError {
			LogError(error)
		}
	}
	
	/// Checks camera availability and delivers the result via `completion`.
	///
	/// `completion` is always invoked on the main actor. For already-determined
	/// authorization states it is called synchronously; for `.notDetermined` it is
	/// called asynchronously once the system permission prompt resolves.
	public func isCameraAvailable(completion: @escaping (Bool) -> Void) {
		let authStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
		switch authStatus {
		case .authorized:
			completion(true)
		case .denied, .restricted:
			completion(false)
		case .notDetermined:
			self.requestCameraAccess(completion: completion)
		default:
			self.requestCameraAccess(completion: completion)
		}
	}
	
	// MARK: - PRIVATE
	
	private func addPreviewLayer() {
		guard let captureSession = self.captureSession else {
			LogWarn("Capture session is nil; cannot add preview layer")
			return
		}
		self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
		self.previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
		self.previewLayer?.frame = self.view.bounds
		guard let preview = self.previewLayer else {
			LogWarn("We couldn't add preview layer in the view")
			return }
		self.view.layer.addSublayer(preview)
	}
	
	private func requestCameraAccess(completion: @escaping (Bool) -> Void) {
		// Bridge AVFoundation's @Sendable completion-handler API to async/await so we don't
		// capture the non-Sendable `completion` inside a @Sendable closure. A Task is needed
		// because the public isCameraAvailable(completion:) API cannot become async without
		// breaking callers; the result is delivered back on the main actor.
		Task { @MainActor in
			let granted = await AVCaptureDevice.requestAccess(for: .video)
			completion(granted)
		}
	}
	
	// MARK: - AVCaptureMetadataOutputObjectsDelegate
	
	public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
		for metadata in metadataObjects {
			
			let readableCode = metadata as? AVMetadataMachineReadableCodeObject
			guard   let value = readableCode?.stringValue,
				let type = readableCode?.type
				else {return}
			
			self.scannerOutput?.didSuccessfullyScan(value, type: type.rawValue)
		}
	}
}
