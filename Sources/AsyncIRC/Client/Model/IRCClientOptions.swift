import NIOCore




public struct ClientContext {
    
    public struct ServerClientInfo: Codable {
        
        public var hostname: String
        public var port: Int
        public var password: String
        public var tls: Bool = true
        
        public init(
            hostname: String = "localhost",
            port: Int = 6667,
            password: String = "",
            tls: Bool = true
        ) {
            self.hostname = hostname
            self.port = port
            self.password = password
            self.tls = tls
        }
    }
    
    public var userInfo: IRCUserInfo
    public var nickname: NeedleTailNick
    public var clientInfo: ServerClientInfo
    
    public init(
        clientInfo: ServerClientInfo,
        nickname: NeedleTailNick
    ) {
        self.clientInfo = clientInfo
        self.nickname = nickname
        self.userInfo = IRCUserInfo(
            username: nickname.stringValue,
            hostname: clientInfo.hostname,
            servername: clientInfo.hostname,
            realname: "Real name is secret")
        
//        super.init(hostname: hostname, port: port, password: password, tls: tls)
    }
    
    
    public var description: String {
        var ms = "<\(type(of: self)):"
        appendToDescription(&ms)
        ms += ">"
        return ms
    }
    
    public func appendToDescription(_ ms: inout String) {
        ms += " \(clientInfo.hostname):\(clientInfo.port)"
        ms += " \(nickname)"
        ms += " \(userInfo)"
        ms += " pwd"
        ms += " has-retryStrategy-cb"
    }
}
