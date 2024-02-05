//
//  DestructionMetadata.swift
//  
//
//  Created by Cole M on 9/4/23.
//

import Foundation

public struct DestructionMetadata: Identifiable {
    
    public let id = UUID()
    public var title: DestructiveMessageTimes
    public var timeInterval: Int
    
    public init(title: DestructiveMessageTimes, timeInterval: Int) {
        self.title = title
        self.timeInterval = timeInterval
    }
}

public enum DestructiveMessageTimes: String {
    case off = "Off"
    case custom = "Custom"
    case thirtyseconds = "30 Seconds"
    case fiveMinutes = "5 Minutes"
    case oneHour = "1 Hours"
    case eightHours = "8 Hours"
    case oneDay = "1 Day"
    case oneWeek = "1 Week"
    case fourWeeks = "4 Weeks"
}
