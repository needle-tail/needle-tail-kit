import Logging
import NeedleTailHelpers

enum IRCTaskHelpers: Sendable {
    @ParsingActor
    static func parseMessageTask(
        task: String,
        messageParser: MessageParser
    ) async throws -> IRCMessage {
        return try await messageParser.parseMessage(task)
    }
}
