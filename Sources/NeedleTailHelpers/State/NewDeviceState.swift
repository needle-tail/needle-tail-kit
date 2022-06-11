//
//  File.swift
//  
//
//  Created by Cole M on 5/28/22.
//

import Foundation

public enum NewDeviceState: Codable {
    case accepted, rejected, waiting, isOffline
}
public var newDeviceState: NewDeviceState = .waiting
