//
//  File.swift
//  
//
//  Created by Cole M on 12/11/21.
//

import Foundation

public struct IRCTags: Hashable, Codable {
    
    public typealias StringLiteralType = String
    
    
    public let key: String
    public let value: String
    
    @inlinable
    public init(
        key: String,
        value: String
    ) {
        self.key = key
        self.value = value
    }
    
    @inlinable
    public var stringValue: String {
        return key
    }
    
    @inlinable
    public func hash(into hasher: inout Hasher) {
        key.hash(into: &hasher)
    }
    
    @inlinable
    public static func ==(lhs: IRCTags, rhs: IRCTags) -> Bool {
        return lhs.key == rhs.key
    }
    
    @inlinable
    public static func validate(string: String) -> Bool {
        guard string.count < 4096 else {
            return false
        }
        return true
    }
}
