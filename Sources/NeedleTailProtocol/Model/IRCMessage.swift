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

import Foundation

/**
 * An IRC message
 *
 * An optional origin, an optional target and the actual command (including its
 * arguments).
 *
 * True origin of message. Do not set in clients.
 *
 * Examples:
 * - `:helge55!~textual@213.211.198.125`
 * - `:helge99`
 * - `:cherryh.freenode.net`
 *
 * This is a server name or a nickname w/ user@host parts.
 */
public struct IRCMessage: Codable, Sendable {

    public var id = UUID()
    public var origin: String?
    public var target: String?
    ///The IRC command and its arguments (max 15).
    public var command: IRCCommand
    public var arguments: [String]?
    public var tags: [IRCTags]?
    public var description: String? {
        var ms = "<IRCMsg:"
        if let tags = tags {
            for tag in tags {
                ms += "@\(tag.key)=\(tag.value);"
            }
        }
        if let origin = origin { ms += " from=\(origin)" }
        if let target = target { ms += " to=\(target)" }
        ms += " "
        ms += command.description
        ms += ">"
        return ms
    }
    
    public init(
        origin: String? = nil,
        target: String? = nil,
        command: IRCCommand,
        arguments: [String]? = nil,
        tags: [IRCTags]? = nil
    ) {
        self.origin = origin
        self.target = target
        self.command = command
        self.arguments = arguments
        self.tags = tags
    }
    
    
    
    public enum CodingKeys: String, Sendable, CodingKey {
        case origin, target, arguments, command, tags
    }

//    // MARK: - Codable
    public init(from decoder: Decoder) async throws {
        let containter = try decoder.container(keyedBy: CodingKeys.self)
        self.origin = try containter.decodeIfPresent(String.self, forKey: .origin)
        do {
            self.command = try containter.decode(IRCCommand.self, forKey: .command)
            self.arguments = try containter.decodeIfPresent([String].self, forKey: .arguments)
        } catch {
            let cmd = try containter.decode(String.self, forKey: .command)
            let arguments = try containter.decodeIfPresent([String].self, forKey: .arguments)
            self.command = try IRCCommand(cmd, arguments: arguments ?? [])
        }
        self.tags = try containter.decodeIfPresent([IRCTags].self, forKey: .tags)
//        let cmd = try c.decode(String.self, forKey: .command)
//        let arguments = try c.decodeIfPresent([ String ].self, forKey: .arguments)
//        let command = try IRCCommand(cmd, arguments: arguments ?? [])
//        let tags = try c.decodeIfPresent([IRCTags].self, forKey: .tags)
//        self.init(origin: try c.decodeIfPresent(String.self, forKey: .origin),
//                  target: try c.decodeIfPresent(String.self, forKey: .target),
//                  command: command,
//                  tags: tags
//        )
    }

    public func encode(to encoder: Encoder) throws {
        var containter = encoder.container(keyedBy: CodingKeys.self)
        try containter.encodeIfPresent(origin, forKey: .origin)
        try containter.encodeIfPresent(target, forKey: .target)
        try containter.encode(command, forKey: .command)
//        try containter.encode(command.commandAsString, forKey: .command)
//        try containter.encode(command.arguments, forKey: .arguments)
        try containter.encodeIfPresent(tags, forKey: .tags)
    }
}

extension IRCMessage: Equatable {
    public static func == (lhs: IRCMessage, rhs: IRCMessage) -> Bool {
        return lhs.id == rhs.id
    }
}
