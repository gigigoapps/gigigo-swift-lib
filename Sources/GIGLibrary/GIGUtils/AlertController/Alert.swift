//
//  GIGMainAlert.swift
//  GIGLibrary
//
//  Created by Alfonso Miranda Castro on 2/2/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import UIKit

@MainActor
protocol AlertInterface {
    func show()
    func addDefaultButton(_ title: String, usingAction: ((String) -> Void)?)
    func addCancelButton(_ title: String, usingAction: ((String) -> Void)?)
    func addDestructiveButton(_ title: String, usingAction: ((String) -> Void)?)
}

@MainActor
open class Alert: NSObject {
    
    internal let interface: AlertInterface

    internal override init() {
        self.interface = AlertController()
        super.init()
    }

    public init(title: String, message: String) {
        self.interface = AlertController(title: title, message: message)
        super.init()
    }
    
    open func show() {
        self.interface.show()
    }
    
    open func addDefaultButton(_ title: String, usingAction: ((String) -> Void)?) {
        self.interface.addDefaultButton(title, usingAction: usingAction)
    }
    
    open func addCancelButton(_ title: String, usingAction: ((String) -> Void)?) {
        self.interface.addCancelButton(title, usingAction: usingAction)
    }
    
    open func addDestructiveButton(_ title: String, usingAction: ((String) -> Void)?) {
        self.interface.addDestructiveButton(title, usingAction: usingAction)

    }
}
