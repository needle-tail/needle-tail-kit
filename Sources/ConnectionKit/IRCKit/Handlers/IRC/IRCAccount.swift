//
//  IRCAccount.swift
//  Cartisim
//
//  Created by Cole M on 9/18/21.
//  Copyright © 2021 Cole M. All rights reserved.
//

import Foundation
import struct Foundation.UUID
import let NIOIRC.DefaultIRCPort

public final class IRCAccount:  Codable, Identifiable {
  
  public let id               : UUID
  public var host             : String
  public var port             : Int
  public var nickname         : String
  public var activeRecipients : [ String ]
  public var tls              : Bool
  
  public var joinedChannels : [ String ] {
    return activeRecipients.filter { $0.hasPrefix("#") }
  }
  
  public init(id: UUID = UUID(),
              host: String, port: Int = DefaultIRCPort,
              nickname: String,
              activeRecipients: [ String ] = [ "#NIO", "#Cartisim" ],
              tls: Bool = false)
  {
    self.id               = id
    self.host             = host
    self.port             = port
    self.nickname         = nickname
    self.activeRecipients = activeRecipients
    self.tls              = tls
  }
  
  
  // MARK: - Arrgh, Codable
  
  enum CodingKeys: CodingKey {
    case id, host, port, nickname, activeRecipients, tls
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    
    self.id       = try container.decode(UUID.self,   forKey: .id)
    self.host     = try container.decode(String.self, forKey: .host)
    self.port     = try container.decode(Int.self,    forKey: .port)
    self.nickname = try container.decode(String.self, forKey: .nickname)
    self.activeRecipients = try container.decode([String].self, forKey: .activeRecipients)
    self.tls      = try container.decode(Bool.self, forKey: .tls)
  }
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encode(id,               forKey: .id)
    try container.encode(host,             forKey: .host)
    try container.encode(port,             forKey: .port)
    try container.encode(nickname,         forKey: .nickname)
    try container.encode(activeRecipients, forKey: .activeRecipients)
    try container.encode(tls, forKey: .tls)
  }
}

extension IRCAccount: CustomStringConvertible {
  public var description: String {
    var ms = "<Account: \(id) \(host):\(port) \(nickname) \(tls)"
    ms += " " + activeRecipients.joined(separator: ",")
    ms += ">"
    return ms
  }
}
