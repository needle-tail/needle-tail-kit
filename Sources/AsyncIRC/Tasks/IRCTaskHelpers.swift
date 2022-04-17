import Foundation
import Logging


enum IRCTaskHelpers {
     static func parseMessageTask(task: String, ircMessageParser: IRCMessageParser) throws -> IRCMessage {
        Logger(label: "IRCTaskHelpers - ").info("Parsing has begun")
            return try ircMessageParser.parseMessage(task)
    }
}
