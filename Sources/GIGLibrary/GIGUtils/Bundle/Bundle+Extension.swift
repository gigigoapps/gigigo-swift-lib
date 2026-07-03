//
//  File.swift
//  
//
//  Created by Alejandro Jiménez on 20/9/22.
//

import Foundation

extension Bundle {
    
    public class func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "no_version"
    }
    
    public class func buildVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "no_version"
    }
    
}
