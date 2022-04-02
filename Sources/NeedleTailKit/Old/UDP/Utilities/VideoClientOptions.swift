//
//  File.swift
//  
//
//  Created by Cole M on 10/9/21.
//

import Foundation
import AsyncIRC





//public class VideoClientOptions : ClientOptions {
//
//    open var password      : String?
//    open var nickname      : IRCNickName
//    open var userInfo      : IRCUserInfo
//    open var retryStrategy : RetryStrategyCB?
//
//
//
//
//    public convenience init(nickname: String) {
//        self.init(nickname: IRCNickName(nickname)!)
//    }
//
//    public init(port           : Int             = 8081,
//                host           : String          = "localhost",
//                tls            : Bool            = false,
//                password       : String?         = nil,
//                nickname       : IRCNickName,
//                userInfo       : IRCUserInfo?    = nil
//    )
//    {
//        self.password      = password
//        self.nickname      = nickname
//        self.retryStrategy = nil
//
//        self.userInfo = userInfo ??  IRCUserInfo(username: nickname.stringValue,
//                                                 hostname: host,
//                                                 servername: host,
//                                                realname: "NIO User")
//
//        super.init(host: host, port: port, tls: tls)
//    }
//
//    override public func appendToDescription(_ ms: inout String) {
//        super.appendToDescription(&ms)
//        ms += " \(nickname)"
//        ms += " \(userInfo)"
//        if password      != nil { ms += " pwd"                  }
//        if retryStrategy != nil { ms += " has-retryStrategy-cb" }
//    }
//}
