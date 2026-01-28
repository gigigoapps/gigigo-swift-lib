//
//  ImageDownloader.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo on 3/11/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import UIKit

@MainActor
struct ImageDownloader {
    
    static let shared = ImageDownloader()
    static var queue: [UIImageView: Request] = [:]
    static var stack: [UIImageView] = []
    static var images: [String: UIImage] = [:]
    
    
    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                ImageDownloader.images = [:]
                ImageDownloader.stack = []
                ImageDownloader.queue = [:]
            }
        }
    }
    
    // MARK: - Public methods
    
    func download(url: String, for view: UIImageView, placeholder: UIImage?) {
        if let request = ImageDownloader.queue[view] {
            request.cancel()
            ImageDownloader.queue.removeValue(forKey: view)
        }
        if let image = ImageDownloader.images[url] {
            view.image = image
        } else {
            view.image = placeholder
            self.loadImage(url: url, in: view)
        }
    }
    
    // MARK: - Private Helpers
    
    private func loadImage(url: String, in view: UIImageView) {
        let request = Request(method: .get, baseUrl: url, endpoint: "", bodyParams: nil)
        ImageDownloader.queue[view] = request
        ImageDownloader.stack.append(view)
        if ImageDownloader.stack.count <= 3 {
            self.downloadNext()
        }
    }
    
    private func downloadNext() {
        guard let view = ImageDownloader.stack.popLast() else { return }
        guard let request = ImageDownloader.queue[view] else {
            return
        }
        let requestedBaseURL = request.baseURL
        request.fetch { response in
            switch response.status {
            case .success:
                guard let image = try? response.image() else {
                    LogWarn("While downloading the image, the body was empty or the image type was not recognized.")
                    self.downloadNext()
                    return
                }
                let width = view.width() * UIScreen.main.scale
                let height = view.height() * UIScreen.main.scale
                DispatchQueue(label: "com.gigigo.imagedownloader", qos: .background).async {
                    var finalImage = image
                    if let resized = image.imageProportionally(with: CGSize(width: width, height: height)) {
                        finalImage = resized
                    }
                    Task { @MainActor in
                        if let currentRequest = ImageDownloader.queue[view], requestedBaseURL == currentRequest.baseURL {
                            self.setAnimated(image: finalImage, in: view)
                        }
                        if let index = ImageDownloader.queue.index(forKey: view) {
                            ImageDownloader.queue.remove(at: index)
                            ImageDownloader.images.updateValue(finalImage, forKey: requestedBaseURL)
                        }
                        self.downloadNext()
                    }
                }
            default:
                LogError(response.error)
                self.downloadNext()
                
            }
        }
    }
    
    private func setAnimated(image: UIImage?, in view: UIImageView) {
        UIView.transition(
            with: view,
            duration: 0.4,
            options: .transitionCrossDissolve,
            animations: {
                view.image = image
            },
            completion: nil
        )
    }
    
}
