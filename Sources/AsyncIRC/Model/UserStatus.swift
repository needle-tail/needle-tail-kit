//
//  File.swift
//  
//
//  Created by Cole M on 3/31/22.
//

import Foundation

public enum UserStatus<T> {
    case wasOffline(T)
    case isOnline
}
