import NeedleTailHelpers

public enum AsyncMessageTask: Sendable {
    @ParsingActor
    public static func parseMessageTask(
        task: String,
        messageParser: MessageParser
    ) async -> IRCMessage? {
        do {
            return try await messageParser.parseMessage(task)
        } catch {
            print(error)
            return nil
        }
    }
}
