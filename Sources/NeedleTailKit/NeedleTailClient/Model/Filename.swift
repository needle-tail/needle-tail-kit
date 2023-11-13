//
//  Filename.swift
//  
//
//  Created by Cole M on 9/4/23.
//

import Foundation

#if (os(macOS) || os(iOS))
public struct Filename: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    
    public var description: String { raw }
    public let raw: String
    
    public init(stringLiteral value: String) {
        self.init(value)
    }
    
    public init(_ description: String) {
        self.raw = description.lowercased()
    }
    
    public static func ==(lhs: Filename, rhs: Filename) -> Bool {
        lhs.raw == rhs.raw
    }
    
    public static func <(lhs: Filename, rhs: Filename) -> Bool {
        lhs.raw < rhs.raw
    }
    
    public func encode(to encoder: Encoder) throws {
        try raw.encode(to: encoder)
    }
}
#endif
