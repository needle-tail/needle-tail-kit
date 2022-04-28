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

import protocol NIO.EventLoopGroup
import class    NIO.MultiThreadedEventLoopGroup

/// Configuration options for the socket connects
public class ConnectOptions: CustomStringConvertible {
  
  public var hostname       : String?
  public var port           : Int
  public var tls: Bool
    
  public init(hostname: String? = "localhost",
              port: Int = 80,
              tls: Bool = false)
  {
    self.hostname = hostname
    self.port     = port
    self.tls = tls
  }
  
  public var description: String {
    var ms = "<\(type(of: self)):"
    appendToDescription(&ms)
    ms += ">"
    return ms
  }
  
  public func appendToDescription(_ ms: inout String) {
    if let hostname = hostname { ms += " \(hostname):\(port)" }
    else { ms += " \(port)" }
  }
  
}


//public let DefaultIRCPort = 6667

/// Configuration options for the IRC client object
public class IRCClientOptions: ConnectOptions {
  
  public var password: String?
  public var nickname: String
  public var userInfo: IRCUserInfo
  public var retryStrategy: IRCRetryStrategyCB?
//
//  public convenience init(nick: String) {
//      self.init(nick: NeedleTailNick(deviceId: nil, nick: nick).stringValue)
//  }
  public init(
              port: Int = DefaultIRCPort,
              host: String = "localhost",
              password: String? = nil,
              tls: Bool = false,
              nickname: String,
              userInfo: IRCUserInfo? = nil
  ) {
    self.password = password
    self.nickname = nickname
    self.retryStrategy = nil
    
    self.userInfo = userInfo ?? IRCUserInfo(username: nickname,
                                            hostname: host, servername: host,
                                            realname: "Real name is secret")
    
      super.init(hostname: host, port: port, tls: tls)
  }
  
  override public func appendToDescription(_ ms: inout String) {
    super.appendToDescription(&ms)
    ms += " \(nickname)"
    ms += " \(userInfo)"
    if password      != nil { ms += " pwd"                  }
    if retryStrategy != nil { ms += " has-retryStrategy-cb" }
  }
}
