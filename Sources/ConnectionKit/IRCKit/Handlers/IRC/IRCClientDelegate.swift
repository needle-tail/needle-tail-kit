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

import NIOIRC

public protocol IRCClientDelegate {
  
  func client(_ client        : IRCNIOHandler,
              registered nick : IRCNickName,
              with   userInfo : IRCUserInfo)

  func clientFailedToRegister(_ client: IRCNIOHandler)
  
  func client(_ client: IRCNIOHandler, received message: IRCMessage)

  func client(_ client: IRCNIOHandler, messageOfTheDay: String)
  func client(_ client: IRCNIOHandler, notice message:  String,
              for recipients: [ IRCMessageRecipient ])
  func client(_ client: IRCNIOHandler,
              message: String, from user: IRCUserID,
              for recipients: [ IRCMessageRecipient ])

  func client(_ client: IRCNIOHandler, changedUserModeTo mode: IRCUserMode)
  func client(_ client: IRCNIOHandler, changedNickTo     nick: IRCNickName)
  
  func client(_ client: IRCNIOHandler, user: IRCUserID, joined: [ IRCChannelName ])
  func client(_ client: IRCNIOHandler, user: IRCUserID, left:   [ IRCChannelName ],
              with: String?)
  
  func client(_ client: IRCNIOHandler,
              changeTopic: String, of channel: IRCChannelName)
}


// MARK: - Default No-Op Implementations

public extension IRCClientDelegate {
  
  func client(_ client: IRCNIOHandler, registered nick: IRCNickName,
              with userInfo: IRCUserInfo) {}
  func client(_ client: IRCNIOHandler, received message: IRCMessage) {}

  func clientFailedToRegister(_ client: IRCNIOHandler) {}

  func client(_ client: IRCNIOHandler, messageOfTheDay: String) {}
  func client(_ client: IRCNIOHandler,
              notice message: String,
              for recipients: [ IRCMessageRecipient ]) {}
  func client(_ client: IRCNIOHandler,
              message: String, from sender: IRCUserID,
              for recipients: [ IRCMessageRecipient ]) {}
  func client(_ client: IRCNIOHandler, changedUserModeTo mode: IRCUserMode) {}
  func client(_ client: IRCNIOHandler, changedNickTo nick: IRCNickName) {}

  func client(_ client: IRCNIOHandler,
              user: IRCUserID, joined channels: [ IRCChannelName ]) {}
  func client(_ client: IRCNIOHandler,
              user: IRCUserID, left   channels: [ IRCChannelName ],
              with message: String?) {}
  func client(_ client: IRCNIOHandler,
              changeTopic: String, of channel: IRCChannelName) {}
}
//
//@_exported import protocol NIO.EventLoopGroup
//@_exported import enum     NIOIRC.IRCCommand
//@_exported import struct   NIOIRC.IRCMessage
//@_exported import struct   NIOIRC.IRCNickName
//@_exported import struct   NIOIRC.IRCChannelName
//@_exported import struct   NIOIRC.IRCUserInfo
//@_exported import enum     NIOIRC.IRCMessageRecipient
//@_exported import struct   NIOIRC.IRCUserMode
//@_exported import struct   NIOIRC.IRCUserID
