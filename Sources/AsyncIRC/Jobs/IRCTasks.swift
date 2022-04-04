import Foundation
import Logging


public struct ParseMessageTask: Codable {
    private enum CodingKeys: String, CodingKey {
        case message = "a"
    }

    let message: String
}

enum IRCTaskHelpers {

     static func parseMessageTask(task: ParseMessageTask, ircMessageParser: IRCMessageParser) async throws -> IRCMessage {
        Logger(label: "IRCTaskHelpers - ").info("Parsing has begun")
            return try await ircMessageParser.parseMessage(task.message)
    }
}
