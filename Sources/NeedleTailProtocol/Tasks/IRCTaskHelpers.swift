import NeedleTailHelpers

public enum AsyncMessageTask: Sendable {
    @ParsingActor
    public static func parseMessageTask(
        task: String,
        messageParser: MessageParser
    ) async throws -> IRCMessage {
        return try await messageParser.parseMessage(task)
    }
}
