//
//  IRCConversation.swift
//  Cartisim
//
//  Created by Cole M on 9/18/21.
//  Copyright © 2021 Cole M. All rights reserved.
//

import Foundation
import NIOIRC

public final class IRCConversation: Identifiable {
  
  public enum ConversationType: Equatable {
    case channel
    case im
  }
  
  public var recipient : IRCMessageRecipient? {
    switch type {
      case .channel:
        guard let name = IRCChannelName(name) else { return nil }
        return .channel(name)
      case .im:
        guard let name = IRCNickName(name)    else { return nil }
        return .nickname(name)
    }
  }
  
  internal private(set) weak var service : IRCClient?
  
  public var type : ConversationType
  public var name : String
  public var id   : String { return name }
  
var timeline = [ TimelineEntry ]()
  
  init(channel: IRCChannelName, service: IRCClient) {
    self.type      = .channel
    self.name      = channel.stringValue
    self.service   = service
  }
  init?(nickname: String, service: IRCClient) {
    self.type      = .im
    self.name      = nickname
    self.service   = service
  }

  convenience init?(channel: String, service: IRCClient) {
    guard let name = IRCChannelName(channel) else { return nil }
    self.init(channel: name, service: service)
  }

  
  // MARK: - Subscription Changes
  
  internal func userDidLeaveChannel() {
    // have some state reflecting that?
  }
  
  
  // MARK: - Connection Changes
  
  internal func serviceDidGoOffline() {
    guard let last = timeline.last else { return }
    if case .disconnect = last.payload { return }

    timeline.append(.init(date: Date(), payload: .disconnect))
  }
  internal func serviceDidGoOnline() {
    guard let last = timeline.last else { return }

    switch last.payload {
      case .reconnect, .message, .notice, .ownMessage:
        return
      case .disconnect:
        break
    }

    timeline.append(.init(date: Date(), payload: .reconnect))
  }
  
  
  // MARK: - Sending Messages

  @discardableResult
  public func sendMessage(_ message: String) -> Bool {
    guard let recipient = recipient                   else { return false }
    guard let service = service                       else { return false }
    guard service.sendMessage(message, to: recipient) else { return false }
    timeline.append(.init(payload: .ownMessage(message)))
    return true
  }
  
  
  // MARK: - Receiving Messages
  
  public func addMessage(_ message: String, from sender: IRCUserID) {
    timeline.append(.init(payload: .message(message, sender)))
  }
  public func addNotice(_ message: String) {
    timeline.append(.init(payload: .notice(message)))
  }
}

extension IRCConversation: CustomStringConvertible {
  public var description: String { "<Conversation: \(type) \(name)>" }
}


import struct Foundation.Date

public struct TimelineEntry: Equatable {
  
  public enum Payload: Equatable {
    
    case ownMessage(String)
    case message(String, IRCUserID)
    case notice (String)

    case disconnect
    case reconnect
  }
  
  public let date    : Date
  public let payload : Payload
  
  init(date: Date = Date(), payload: Payload) {
    self.date    = date
    self.payload = payload
  }
}
