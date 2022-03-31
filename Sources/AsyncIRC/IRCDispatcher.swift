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

#if compiler(>=5.5) && canImport(_Concurrency)

/**
 * Dispatches incoming IRCMessage's to protocol methods.
 *
 * This has a main entry point `irc_msgSend` which takes an `IRCMessage` and
 * then calls the respective protocol functions matching the command of the
 * message.
 *
 * If a dispatcher doesn't implement a method, the
 * `IRCDispatcherError.doesNotRespondTo`
 * error is thrown.
 *
 * Note: Implementors *can* re-implement `irc_msgSend` and still access the
 *       default implementation by calling `irc_defaultMsgSend`. Which contains
 *       the actual dispatcher implementation.
 */

public protocol IRCDispatcher {
    // MARK: - Dispatching Function
    func irc_msgSend(_ message: IRCMessage) async throws
    
    // MARK: - Implementations
    func doPing      (_ server   : String,
                      server2    : String?)            async throws
    func doCAP       (_ cmd      : IRCCommand.CAPSubCommand,
                      _ capIDs   : [ String ])         async throws
    
    func doNick      (_ nick     : IRCNickName, tags: [IRCTags]?)        async throws
    func doUserInfo  (_ info     : IRCUserInfo, tags: [IRCTags]?)        async throws
    func doModeGet   (nick       : IRCNickName)        async throws
    func doModeGet   (channel    : IRCChannelName)     async throws
    func doMode      (nick       : IRCNickName,
                      add        : IRCUserMode,
                      remove     : IRCUserMode)        async throws
    
    func doWhoIs     (server     : String?,
                      usermasks  : [ String ])         async throws
    func doWho       (mask       : String?, operatorsOnly opOnly: Bool) async throws
    
    func doJoin      (_ channels : [ IRCChannelName ]) async throws
    func doPart      (_ channels : [ IRCChannelName ],
                      message    : String?)            async throws
    func doPartAll   ()                                async throws
    func doGetBanMask(_ channel  : IRCChannelName)     async throws
    
    func doNotice    (recipients : [ IRCMessageRecipient ],
                      message    : String) async throws
    func doMessage   (sender     : IRCUserID?,
                      recipients : [ IRCMessageRecipient ],
                      message    : String,
                      tags: [IRCTags]?,
                      userStatus: UserStatus<Any>?) async throws
    
    func doIsOnline  (_ nicks    : [ IRCNickName ]) async throws
    
    func doList      (_ channels : [ IRCChannelName ]?,
                      _ target   : String?)         async throws
    
    func doQuit      (_ message  : String?) async throws
    
    func doPublishKeyBundle(_ keyBundle: [String]) async throws
    
    func doReadKeyBundle(_ keyBundle: [String]) async throws
    
    func doRegisterAPN(_ token: [String]) async throws
}

public enum IRCDispatcherError : Swift.Error {
    
    case doesNotRespondTo(IRCMessage)
    
    case nicknameInUse(IRCNickName)
    case noSuchNick   (IRCNickName)
    case noSuchChannel(IRCChannelName)
    case alreadyRegistered
    case notRegistered
    case cantChangeModeForOtherUsers
    case nilUserConfig
}

public extension IRCDispatcher {
    
    func irc_msgSend(_ message: IRCMessage) async throws {
        try await irc_defaultMsgSend(message)
    }
    
    func irc_defaultMsgSend(_ message: IRCMessage) async throws {
        do {
            switch message.command {
                
            case .PING(let server, let server2):
                try await doPing(server, server2: server2)
                
            case .PRIVMSG(let recipients, let payload):
                let sender = message.origin != nil
                ? IRCUserID(message.origin!) : nil
                let tags = message.tags
                try await doMessage(sender: sender,
                                    recipients: recipients,
                                    message: payload,
                                    tags: tags,
                                    userStatus: nil)
            case .NOTICE(let recipients, let message):
                try await doNotice(recipients: recipients, message: message)
            case .NICK(let nickName):
                try await doNick(nickName, tags: message.tags)
            case .USER(let info):
                try await doUserInfo(info, tags: message.tags)
            case .ISON(let nicks):
                try await doIsOnline(nicks)
            case .MODEGET(let nickName):
                try await doModeGet(nick: nickName)
            case .CAP(let subcmd, let capIDs):
                try await doCAP(subcmd, capIDs)
            case .QUIT(let message):
                try await doQuit(message)
            case .CHANNELMODE_GET(let channelName):
                try await doModeGet(channel: channelName)
            case .CHANNELMODE_GET_BANMASK(let channelName):
                try await doGetBanMask(channelName)
                
            case .MODE(let nickName, let add, let remove):
                try await doMode(nick: nickName, add: add, remove: remove)
                
            case .WHOIS(let server, let masks):
                try await doWhoIs(server: server, usermasks: masks)
                
            case .WHO(let mask, let opOnly):
                try await doWho(mask: mask, operatorsOnly: opOnly)
                
            case .JOIN(let channels, _): try await doJoin(channels)
            case .JOIN0:                 try await doPartAll()
                
            case .PART(let channels, let message):
                try await doPart(channels, message: message)
                
            case .LIST(let channels, let target):
                try await doList(channels, target)
            case .otherCommand("PUBKEYBNDL", let keyBundle):
                try await doPublishKeyBundle(keyBundle)
            case .otherCommand("READKEYBNDL", let keyBundle):
                try await doReadKeyBundle(keyBundle)
            case .otherCommand("REGAPN", let token):
                try await doRegisterAPN(token)
            default:
                throw IRCDispatcherError.doesNotRespondTo(message)
            }
        }
        catch let error as InternalDispatchError {
            switch error {
            case .notImplemented:
                throw IRCDispatcherError.doesNotRespondTo(message)
            }
        }
        catch {
            throw error
        }
    }
}

fileprivate enum InternalDispatchError : Swift.Error {
    case notImplemented(function: String)
}


public extension IRCDispatcher {
    
    func doPing(_ server: String, server2: String?) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    
    func doCAP(_ cmd: IRCCommand.CAPSubCommand, _ capIDs: [ String ]) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    
    func doNick(_ nick: IRCNickName, tags: [IRCTags]?) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doUserInfo(_ info: IRCUserInfo, tags: [IRCTags]?) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doModeGet(nick: IRCNickName) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doModeGet(channel: IRCChannelName) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doMode(nick: IRCNickName, add: IRCUserMode, remove: IRCUserMode) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    
    func doWhoIs(server: String?, usermasks: [ String ]) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doWho(mask: String?, operatorsOnly opOnly: Bool) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    
    func doJoin(_ channels: [ IRCChannelName ]) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doPart(_ channels: [ IRCChannelName ], message: String?) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doPartAll() async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doGetBanMask(_ channel: IRCChannelName) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    
    func doNotice(recipients: [ IRCMessageRecipient ], message: String) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doMessage(sender: IRCUserID?,
                   recipients: [ IRCMessageRecipient ],
                   message: String,
                   tags: [IRCTags]? = nil,
                   userStatus: UserStatus<Any>?) async throws
    {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    
    func doIsOnline(_ nicks: [ IRCNickName ]) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doList(_ channels : [ IRCChannelName ]?, _ target: String?) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    
    func doQuit(_ message: String?) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    
    func doPublishKeyBundle(_ keyBundle: [String]) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    
    func doReadKeyBundle(_ keyBundle: [String]) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    
    func doRegisterAPN(_ token: [String]) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
}
#endif
