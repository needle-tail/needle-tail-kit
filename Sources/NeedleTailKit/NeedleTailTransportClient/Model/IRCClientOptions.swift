import NIOCore
import AsyncIRC

 public struct ClientContext {
    
     public struct ServerClientInfo: Codable {
        
         var hostname: String
         var port: Int
         var password: String
         var tls: Bool = true
        
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
    
     var userInfo: IRCUserInfo
     var nickname: NeedleTailNick
     var clientInfo: ServerClientInfo
    
     init(
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
    }
    
    
     var description: String {
        var ms = "<\(type(of: self)):"
        appendToDescription(&ms)
        ms += ">"
        return ms
    }
    
     func appendToDescription(_ ms: inout String) {
        ms += " \(clientInfo.hostname):\(clientInfo.port)"
        ms += " \(nickname)"
        ms += " \(userInfo)"
        ms += " pwd"
        ms += " has-retryStrategy-cb"
    }
}
