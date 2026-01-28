//
//  GIGIOSVersion.swift
//  GIGLibrary
//
//  Created by Alfonso Miranda Castro on 3/2/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import Foundation
import UIKit

@MainActor let Device = UIDevice.current
@MainActor let iosVersion = NSString(string: Device.systemVersion).doubleValue

@MainActor let MAJORTHANIOS8 = (iosVersion > 8.0)
@MainActor let iOS7 = (iosVersion < 8)
