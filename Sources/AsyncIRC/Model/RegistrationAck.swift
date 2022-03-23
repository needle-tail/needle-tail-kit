//
//  File.swift
//  
//
//  Created by Cole M on 3/23/22.
//

import Foundation


public struct RegistrationAck: Codable {
    public var registered: Bool
    
    public init(registered: Bool) {
        self.registered = registered
    }
}
