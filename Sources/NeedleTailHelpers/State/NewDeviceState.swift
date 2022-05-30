//
//  File.swift
//  
//
//  Created by Cole M on 5/28/22.
//

import Foundation

public enum NewDeviceState: Codable {
    case accepted, rejected, waiting
}
public var newDeviceState: NewDeviceState = .waiting
