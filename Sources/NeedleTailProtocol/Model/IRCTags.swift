//
//  IRCTags.swift
//  
//
//  Created by Cole M on 12/11/21.
//

public struct IRCTags: Hashable, Codable, Sendable {
    
    public typealias StringLiteralType = String
    
    
    public let key: String
    public let value: String
    
    public init(
        key: String,
        value: String
    ) {
        self.key = key
        self.value = value
    }
    
    public var stringValue: String {
        return key
    }
    
    public func hash(into hasher: inout Hasher) {
        key.hash(into: &hasher)
    }
    
    public static func ==(lhs: IRCTags, rhs: IRCTags) -> Bool {
        return lhs.key == rhs.key
    }
    
    public static func validate(string: String) -> Bool {
        guard string.count < 4096 else {
            return false
        }
        return true
    }
}
