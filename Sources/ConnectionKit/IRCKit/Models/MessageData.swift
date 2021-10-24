import Foundation

public struct MessageData: Codable {
    public var avatar: String? = ""
    public var userID: String? = ""
    public var name: String? = ""
    public var message: String? = ""
    public var accessToken: String? = ""
    public var refreshToken: String? = ""
    public var sessionID: String? = ""
    public var chatSessionID: String? = ""
    
    public init(
        avatar: String? = "",
        userID: String? = "",
        name: String? = "",
        message: String? = "",
        accessToken: String? = "",
        refreshToken: String? = "",
        sessionID: String? = "",
        chatSessionID: String? = ""
    ) {
        self.avatar = avatar
        self.userID = userID
        self.name = name
        self.message = message
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.sessionID = sessionID
        self.chatSessionID = chatSessionID
    }
}

