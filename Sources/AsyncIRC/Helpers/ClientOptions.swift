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

import Foundation

public class ClientOptions {
    
    public var host: String?
    public var port: Int?
    public var password: String = ""
    public var tls: Bool = true
    public var userInfo: IRCUserInfo?
    
    public init(
        host: String?,
        port: Int?,
        password: String,
        tls: Bool,
        userInfo: IRCUserInfo? = nil
    ) {
        self.host = host
        self.port = port
        self.password = password
        self.tls = tls
        self.userInfo = userInfo
    }
    
    public func appendToDescription(_ ms: inout String) {
        if let hostname = host { ms += " \(hostname):\(port ?? 6667)" }
        else { ms += " \(port ?? 6667)" }
    }
}
