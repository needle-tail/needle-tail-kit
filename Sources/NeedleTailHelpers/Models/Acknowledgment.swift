//
//  Acknowledgment.swift
//  
//
//  Created by Cole M on 3/23/22.
//

import Foundation
import BSON

public struct Acknowledgment: Codable {
    
    public enum AckType: Codable, Equatable {
        case registered(String)
        case registryRequestRejected(String, String)
        case registryRequestAccepted(String, String)
        case newDevice(String)
        case readKeyBundle(String)
        case apn(String)
        case none
        case messageSent(String)
        case blocked
        case unblocked
    }

    public var acknowledgment: AckType
    
    public init(
        acknowledgment: AckType
    ) {
        self.acknowledgment = acknowledgment
    }
}
