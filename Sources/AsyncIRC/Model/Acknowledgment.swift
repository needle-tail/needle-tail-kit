//
//  File.swift
//  
//
//  Created by Cole M on 3/23/22.
//

import Foundation


public struct Acknowledgment: Codable {
    
    public enum AckType: Codable, Equatable {
        case registered(String)
        case readKeyBundle(String)
        case apn(String)
        case none
    }

    public var acknowledgment: AckType
    
    public init(
        acknowledgment: AckType
    ) {
        self.acknowledgment = acknowledgment
    }
}
