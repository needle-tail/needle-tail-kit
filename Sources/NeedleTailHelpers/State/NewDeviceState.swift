//
//  NewDeviceState.swift
//
//
//  Created by Cole M on 5/28/22.
//


public enum NewDeviceState: Equatable, Codable, Sendable {
    case accepted, rejected, waiting, isOffline
}
public var newDeviceState: NewDeviceState = .waiting
