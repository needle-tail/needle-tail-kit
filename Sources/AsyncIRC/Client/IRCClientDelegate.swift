//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-nio-irc open source project
//
// Copyright (c) 2018 ZeeZide GmbH. and the swift-nio-irc project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIOIRC project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/**
 * Delegate methods called by `IRCClient` upon receiving IRC commands.
 */

public protocol IRCClientDelegate: AnyObject {
    func client(_ client        : IRCClient,
                registered nick : IRCNickName,
                with   userInfo : IRCUserInfo) async
    
    func clientFailedToRegister(_ client: IRCClient) async
    func client(_ client: IRCClient, received message: IRCMessage) async
    func client(_ client: IRCClient, messageOfTheDay: String) async
    func client(_ client: IRCClient, notice message:  String,
                for recipients: [ IRCMessageRecipient ]) async
    func client(_ client: IRCClient,
                message: String,
                from user: IRCUserID,
                for recipients: [ IRCMessageRecipient ]) async
    func client(_ client: IRCClient, changedUserModeTo mode: IRCUserMode) async
    func client(_ client: IRCClient, changedNickTo     nick: IRCNickName) async
    func client(_ client: IRCClient, user: IRCUserID, joined: [ IRCChannelName ]) async
    func client(_ client: IRCClient, user: IRCUserID, left:   [ IRCChannelName ],
                with: String?) async
    func client(_ client: IRCClient,
                changeTopic: String, of channel: IRCChannelName) async
    func client(_ client: IRCClient, quit: String?) async
    func client(_ client: IRCClient, info: [String]) async throws
    @InboundActor func client(_ client: IRCClient, keyBundle: [String]) async throws
}


// MARK: - Default No-Op Implementations
public extension IRCClientDelegate {
    
    func client(_ client: IRCClient, registered nick: IRCNickName,
                with userInfo: IRCUserInfo) async {}
    func client(_ client: IRCClient, received message: IRCMessage) async {}
    func clientFailedToRegister(_ client: IRCClient) async {}
    func client(_ client: IRCClient, messageOfTheDay: String) async {}
    func client(_ client: IRCClient,
                notice message: String,
                for recipients: [ IRCMessageRecipient ]) async {}
    func client(_ client: IRCClient,
                message: String, from sender: IRCUserID,
                for recipients: [ IRCMessageRecipient ]) async {}
    func client(_ client: IRCClient, changedUserModeTo mode: IRCUserMode) async {}
    func client(_ client: IRCClient, changedNickTo nick: IRCNickName) async {}
    
    func client(_ client: IRCClient,
                user: IRCUserID, joined channels: [ IRCChannelName ]) async {}
    func client(_ client: IRCClient,
                user: IRCUserID, left   channels: [ IRCChannelName ],
                with message: String?) async {}
    func client(_ client: IRCClient,
                changeTopic: String, of channel: IRCChannelName) async {}
    func client(_ client: IRCClient, quit: String?) async {}
    func client(_ client: IRCClient, info: [String]) async throws {}
    @InboundActor func client(_ client: IRCClient, keyBundle: [String]) async throws {}
}

