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


/// Configuration options for the socket connects
public class ConnectOptions : CustomStringConvertible {
    
    public var hostname       : String?
    public var port           : Int
    public var tls: Bool
    
    public init(
        hostname: String? = "localhost",
        port: Int = 80,
        tls: Bool = false
    )
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
    
    open func appendToDescription(_ ms: inout String) {
        if let hostname = hostname { ms += " \(hostname):\(port)" }
        else { ms += " \(port)" }
    }
    
}


import NIOIRC

public let DefaultIRCPort = 6667

/// Configuration options for the IRC client object
public class IRCClientOptions : ConnectOptions {
    
    open var password      : String?
    open var nickname      : IRCNickName
    open var userInfo      : IRCUserInfo
    open var retryStrategy : IRCRetryStrategyCB?
    
    
    
    
    public convenience init(nick: String) {
        self.init(nickname: IRCNickName(nick)!)
    }
    
    public init(port           : Int             = DefaultIRCPort,
                host           : String          = "localhost",
                tls            : Bool            = false,
                password       : String?         = nil,
                nickname       : IRCNickName,
                userInfo       : IRCUserInfo?    = nil)
    {
        self.password      = password
        self.nickname      = nickname
        self.retryStrategy = nil
        
        self.userInfo = userInfo ?? IRCUserInfo(username: nickname.stringValue,
                                                hostname: host,
                                                servername: host,
                                                realname: "NIO IRC User")
        
        super.init(hostname: host, port: port, tls: tls)
    }
    
    override open func appendToDescription(_ ms: inout String) {
        super.appendToDescription(&ms)
        ms += " \(nickname)"
        ms += " \(userInfo)"
        if password      != nil { ms += " pwd"                  }
        if retryStrategy != nil { ms += " has-retryStrategy-cb" }
    }
}
