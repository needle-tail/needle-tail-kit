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

import NeedleTailHelpers

public protocol IRCDispatcher: AnyObject, Sendable {
    
    // MARK: - Implementations
    func doPing(_ origin: String, origin2: String?) async throws
    func doPong(_ origin: String, origin2: String?) async throws
    func doCAP(_ cmd: IRCCommand.CAPSubCommand, _ capIDs   : [ String ]) async throws
    
    func doNick(_ sender: IRCUserID?, nick: NeedleTailNick, tags: [IRCTags]?) async throws
    func doUserInfo(_ info: IRCUserInfo, tags: [IRCTags]?) async throws
    func doModeGet(nick: NeedleTailNick) async throws
    func doModeGet(channel: IRCChannelName) async throws
    func doMode(nick: NeedleTailNick, add: IRCUserMode, remove: IRCUserMode) async throws
    func doWhoIs(server: String?, usermasks: [ String ]) async throws
    func doWho(mask: String?, operatorsOnly opOnly: Bool) async throws
    
    func doJoin(_ channels: [ IRCChannelName ], tags: [IRCTags]?) async throws
    func doPart(_ channels: [ IRCChannelName ], tags: [IRCTags]?) async throws
    func doPartAll() async throws
    func doGetBanMask(_ channel  : IRCChannelName) async throws
    func doNotice(recipients: [ IRCMessageRecipient ], message: String) async throws
    func doMessage(
        sender: IRCUserID?,
        recipients: [ IRCMessageRecipient ],
        message: String,
        tags: [IRCTags]?
    ) async throws
    func doIsOnline (_ nicks: [ NeedleTailNick ]) async throws
    func doList(_ channels: [ IRCChannelName ]?, _ target: String?) async throws
    func doQuit(_ message: String?) async throws
    func doPublishKeyBundle(_ keyBundle: [String]) async throws
    func doReadKeyBundle(_ keyBundle: [String]) async throws
    func doRegisterAPN(_ token: [String]) async throws
    func doPassword(_ password: [String]) async throws
    func doNewDevice(_ info: [String]) async throws
    func doBlobs(_ blobs: [String]) async throws
    func doReadBlob(_ blob: [String]) async throws
    func doOfflineMessages(_ nick: NeedleTailNick) async throws
    func doDeleteOfflineMessages(from contact: String) async throws
    func doKick(_
                channels: [IRCChannelName],
                users: [NeedleTailNick],
                comments: [String]?
    ) async throws
    func doKill(_ nick: NeedleTailNick, comment: String) async throws
    func doMultipartMessageDownload(_ packet: [String]) async throws
    func doMultipartMessageUpload(_ packet: [String]) async throws
    func doListBucket(_ packet: [String]) async throws
    func badgeCountUpdate(_ count: Int) async throws
}

public extension IRCDispatcher {
    
    func doPing(_ origin: String, origin2: String? = nil) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doPong(_ origin: String, origin2: String? = nil) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doCAP(_ cmd: IRCCommand.CAPSubCommand, _ capIDs: [ String ]) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doNick(_ sender: IRCUserID?, nick: NeedleTailNick, tags: [IRCTags]?) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doUserInfo(_ info: IRCUserInfo, tags: [IRCTags]?) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doModeGet(nick: NeedleTailNick) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doModeGet(channel: IRCChannelName) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doMode(nick: NeedleTailNick, add: IRCUserMode, remove: IRCUserMode) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    
    func doWhoIs(server: String?, usermasks: [ String ]) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doWho(mask: String?, operatorsOnly opOnly: Bool) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    
    func doJoin(_ channels: [ IRCChannelName ], tags: [IRCTags]?) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doPart(_ channels: [ IRCChannelName ], tags: [IRCTags]?) async throws {
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
    func doMessage(
        sender: IRCUserID?,
        recipients: [ IRCMessageRecipient ],
        message: String,
        tags: [IRCTags]?
    ) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doIsOnline(_ nicks: [ NeedleTailNick ]) async throws {
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
    func doPassword(_ password: [String]) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doNewDevice(_ info: [String]) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doBlobs(_ blobs: [String]) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doReadBlob(_ blob: [String]) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doOfflineMessages(_ nick: NeedleTailNick) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doDeleteOfflineMessages(from contact: String) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doKick(_
                channels: [IRCChannelName],
                users: [NeedleTailNick],
                comments: [String]?
    ) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    
    func doKill(_ nick: NeedleTailNick, comment: String) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doMultipartMessageDownload(_ packet: [String]) async throws{
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doMultipartMessageUpload(_ packet: [String]) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func doListBucket(_ packet: [String]) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
    func badgeCountUpdate(_ count: Int) async throws {
        throw InternalDispatchError.notImplemented(function: #function)
    }
}

public enum IRCDispatcherError : Swift.Error {
    case doesNotRespondTo(IRCMessage)
    case nicknameInUse(NeedleTailNick)
    case noSuchNick(NeedleTailNick)
    case noSuchChannel(IRCChannelName)
    case alreadyRegistered
    case notRegistered
    case cantChangeModeForOtherUsers
    case nilUserConfig
    case nilToken
}

fileprivate enum InternalDispatchError : Swift.Error {
    case notImplemented(function: String)
}
