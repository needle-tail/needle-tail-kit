//
//  ClientOptions.swift
//  
//
//  Created by Cole M on 11/28/21.
//

import Foundation
import AsyncIRC

public class ClientOptions {
    
    var host: String?
    var port: Int?
    var password: String?
    var tls: Bool?
    var userInfo: IRCUserInfo?
    
    public init(
        host: String?,
        port: Int?,
        password: String,
        tls: Bool?,
        userInfo: IRCUserInfo? = nil
    ) {
        self.host = host
        self.port = port
        self.password = password
        self.tls = tls
        self.userInfo = userInfo
    }
    
    open func appendToDescription(_ ms: inout String) {
        if let hostname = host { ms += " \(hostname):\(port ?? 6667)" }
        else { ms += " \(port ?? 6667)" }
    }
}
