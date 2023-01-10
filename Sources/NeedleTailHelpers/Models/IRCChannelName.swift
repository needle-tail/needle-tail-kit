//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-nio-irc open source project
//
// Copyright (c) 2018-2021 ZeeZide GmbH. and the swift-nio-irc project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIOIRC project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/**
 * An IRC channel name
 *
 * Channel names are case-insensitive!
 *
 * Strings beginning with a type code (see [IRC-CHAN]):
 * - &, #, +, !
 *
 * - length: max 50
 * - shall not contain spaces
 * - shall not contain ASCII 7 (^G)
 * - shall not contain a ','
 */
//import AsyncKit
import NIOConcurrencyHelpers

/// We are using classes because we want a reference to the object on the server, in order to use ObjectIdentifier to Cache the Object.
/// This class can be Sendable because we are using a lock to protect any mutated state
public final class IRCChannelName: Codable, Hashable, CustomStringConvertible, Sendable {
    
    public typealias StringLiteralType = String
    
    let storage: String
    let normalized: String
    private let lock = NIOLock()
    private static let staticLock = NIOLock()
    
    public init?(_ s: String) {
        guard IRCChannelName.validate(string: s) else { return nil }
        lock.lock()
        storage = s
        normalized = s.ircLowercased()
        lock.unlock()
    }
    
    public var stringValue: String {
        lock.withSendableLock {
            storage
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        lock.lock()
        normalized.hash(into: &hasher)
        lock.unlock()
    }
    
    
    public static func ==(lhs: IRCChannelName, rhs: IRCChannelName) -> Bool {
        return IRCChannelName.staticLock.withSendableLock {
            lhs.normalized == rhs.normalized
        }
    }
    
    public var description: String {
        return lock.withSendableLock {
            stringValue
        }
    }
    
    public static func validate(string: String) -> Bool {
        guard string.count > 1 && string.count <= 50 else { return false }
        
        switch string.first! {
        case "&", "#", "+", "!": break
        default: return false
        }
        
        func isValidCharacter(_ c: UInt8) -> Bool {
            return c != 7 && c != 32 && c != 44
        }
        guard !string.utf8.contains(where: { !isValidCharacter($0) }) else {
            return false
        }
        
        // TODO: RFC 2812 2.3.1
        
        return true
    }
    
    
    public enum CodingKeys: CodingKey, Sendable {
        case storage, normalized
    }
    
    // MARK: - Codable
    public init(from decoder: Decoder) async throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.storage = try container.decode(String.self, forKey: .storage)
        self.normalized = try container.decode(String.self, forKey: .normalized)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storage, forKey: .storage)
        try container.encodeIfPresent(normalized, forKey: .normalized)
    }
}
