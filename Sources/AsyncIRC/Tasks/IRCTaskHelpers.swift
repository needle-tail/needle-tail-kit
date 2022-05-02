import Foundation
import Logging
import NeedleTailHelpers

enum IRCTaskHelpers {
    @ParsingActor
     static func parseMessageTask(task: String, messageParser: MessageParser) async throws -> IRCMessage {
        Logger(label: "IRCTaskHelpers - ").info("Parsing has begun")
            return try await messageParser.parseMessage(task)
    }
}