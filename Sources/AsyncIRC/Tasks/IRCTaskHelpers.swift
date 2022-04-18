import Foundation
import Logging


enum IRCTaskHelpers {
     static func parseMessageTask(task: String, messageParser: MessageParser) throws -> IRCMessage {
        Logger(label: "IRCTaskHelpers - ").info("Parsing has begun")
            return try messageParser.parseMessage(task)
    }
}
