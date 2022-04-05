import Foundation
import Logging


public struct ParseMessageTask: Codable {
    private enum CodingKeys: String, CodingKey {
        case message = "a"
    }

    let message: String
}

enum IRCTaskHelpers {

     static func parseMessageTask(task: String, ircMessageParser: IRCMessageParser) throws -> IRCMessage {
        Logger(label: "IRCTaskHelpers - ").info("Parsing has begun")
            return try ircMessageParser.parseMessage(task)
    }
}
