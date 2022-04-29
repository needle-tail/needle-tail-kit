import CypherMessaging
import NeedleTailHelpers

public protocol IRCMessengerProtocol: AnyObject {
    var origin: String? { get }
    var target: String { get }
    var tags: [IRCTags]? { get }
    func sendAndFlushMessage(_ message: IRCMessage, chatDoc: ChatDocument?) async
}

extension IRCMessengerProtocol {
    //Default value
    public var target: String { get { return "" } set{} }
}

public extension IRCMessengerProtocol {

    //TODO: AFTER WE WORK ON GROUP MESSAGES SEE IF WE CAN REMOVE ARRAY OR RECIPIENTS AND DO THE SAME FOR NOTICE
    func sendIRCMessage(_ message: String, to recipient: IRCMessageRecipient..., tags: [IRCTags]? = nil) async {
        guard !recipient.isEmpty else { return }
        let lines = message.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\r", with: "") }
        _ = await lines.asyncMap {
            let message = IRCMessage(origin: self.origin, command: .PRIVMSG(recipient, $0), tags: tags)
            await self.sendAndFlushMessage(message, chatDoc: nil)
        }
    }
    
    
    func sendIRCNotice(_ message: String, to recipients: [IRCMessageRecipient]) async {
        guard !recipients.isEmpty else { return }
        let lines = message.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\r", with: "") }

        _ = await lines.asyncMap {
            let message = IRCMessage(origin: self.origin, command: .NOTICE(recipients, $0), tags: self.tags)
            await self.sendAndFlushMessage(message, chatDoc: nil)
        }
    }
    
    @NeedleTailKitActor
    func createNeedleTailMessage(_
              command: IRCCommand,
              tags: [IRCTags]? = nil
    ) async {
            let message = IRCMessage(command: command, tags: tags)
            await sendAndFlushMessage(message, chatDoc: nil)
    }
}
