import NeedleTailHelpers

public enum AsyncMessageTask: Sendable {
//    @ParsingActor
    public static func parseMessageTask(
        task: String,
        messageParser: MessageParser
    ) -> IRCMessage? {
        do {
            return try messageParser.parseMessage(task)
        } catch {
            print(error)
            return nil
        }
    }
}
