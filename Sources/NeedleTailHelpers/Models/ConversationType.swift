//
//  ConversationType.swift
//  
//
//  Created by Cole M on 6/18/22.
//

import Foundation

public enum ConversationType: Equatable, Sendable {
    case groupMessage(String)
    case privateMessage
}
