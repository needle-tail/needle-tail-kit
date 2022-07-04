//
//  OnlineStatus.swift
//  
//
//  Created by Cole M on 6/18/22.
//

import Foundation

public enum OnlineStatus: Sendable {
    case wasOffline(ChatDocument)
    case isOnline
}
