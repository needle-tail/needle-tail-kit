//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-nio-irc open source project
//
// Copyright (c) 2018-2020 ZeeZide GmbH. and the swift-nio-irc project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIOIRC project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import Logging
#if canImport(Network)
import NIOTransportServices
#endif

/**
 * A simple IRC client based on SwiftNIO.
 *
 * Checkout swift-nio-irc-eliza or swift-nio-irc-webclient for examples on this.
 *
 * The basic flow is:
 * - create a `IRCClient` object, quite likely w/ custom `IRCClientOptions`
 * - implement and assign an `IRCClientDelegate`, which is going to handle
 *   incoming commands
 * - `connect` the client
 */
public final class IRCClient: IRCClientMessageTarget {
    
    public var origin: String? { return nil }
    public let options: IRCClientOptions
    public let eventLoop: EventLoop
    public weak var delegate: IRCClientDelegate?
    public var tags: [IRCTags]?
    let groupManager: EventLoopGroupManager
    var messageOfTheDay = ""
    internal var state : State = .disconnected
    internal var userMode = IRCUserMode()
    var subscribedChannels = Set<IRCChannelName>()
    
    var usermask : String? {
        guard case .registered(_, let nick, let info) = state else { return nil }
        let host = info.servername ?? options.hostname ?? "??"
        return "\(nick.stringValue)!~\(info.username)@\(host)"
    }
    
    var logger: Logger
    var retryInfo = IRCRetryInfo()
    var channel : Channel? { get { return state.channel } }
    let consumer = Consumer()
    var iterator: MessageSequence.Iterator?
    
    
    public enum Error : Swift.Error {
        case writeError(Swift.Error)
        case stopped
        case notImplemented
        case internalInconsistency
        case unexpectedInput
        case channelError(Swift.Error)
    }
    
    enum State : CustomStringConvertible {
        case disconnected
        case connecting
        case registering(channel: Channel, nick: IRCNickName, userInfo: IRCUserInfo)
        case registered (channel: Channel, nick: IRCNickName, userInfo: IRCUserInfo)
        case error      (Error)
        case requestedQuit
        case quit
        
        var isRegistered : Bool {
            switch self {
            case .registered: return true
            default:          return false
            }
        }
        
        var nick : IRCNickName? {
            get {
                switch self {
                case .registering(_, let v, _): return v
                case .registered (_, let v, _): return v
                default: return nil
                }
            }
        }
        
        var userInfo : IRCUserInfo? {
             get {
                switch self {
                case .registering(_, _, let v): return v
                case .registered (_, _, let v): return v
                default: return nil
                }
            }
        }
        
        var channel : Channel? {
            get {
                switch self {
                case .registering(let channel, _, _): return channel
                case .registered (let channel, _, _): return channel
                default: return nil
                }
            }
        }
        
        var canStartConnection : Bool {
            switch self {
            case .disconnected, .error: return true
            case .connecting:           return false
            case .registering:          return false
            case .registered:           return false
            case .requestedQuit, .quit: return false
            }
        }
        
        var description : String {
            switch self {
            case .disconnected:                return "disconnected"
            case .connecting:                  return "connecting..."
            case .registering(_, let nick, _): return "registering<\(nick)>..."
            case .registered (_, let nick, _): return "registered<\(nick)>"
            case .error      (let error):      return "error<\(error)>"
            case .requestedQuit:               return "quitting..."
            case .quit:                        return "quit"
            }
        }
    }
    
    public init(
        options: IRCClientOptions
    ) {
        self.options = options
        let group: EventLoopGroup?
        self.logger = Logger(label: "NeedleTail Client Logger")
#if canImport(Network)
            if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 3, *) {
                group = NIOTSEventLoopGroup()
            } else {
                print("Sorry, your OS is too old for Network.framework.")
                exit(0)
            }
#else
            group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
#endif

        self.eventLoop = group!.next()
        let provider: EventLoopGroupManager.Provider = group.map { .shared($0) } ?? .createNew
        self.groupManager = EventLoopGroupManager(provider: provider)
        let seq = MessageSequence(consumer: consumer)
        iterator = seq.makeAsyncIterator()
    }
    
    deinit {
        _ = channel?.close(mode: .all)
    }
}

extension IRCClient: Equatable {
    public static func == (lhs: IRCClient, rhs: IRCClient) -> Bool {
        return lhs === rhs
    }
}
