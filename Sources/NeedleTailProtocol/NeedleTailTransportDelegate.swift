import CypherMessaging
import NeedleTailHelpers
import NIOCore


public protocol NeedleTailTransportDelegate: AnyObject {
    @NeedleTailClientActor
    var userConfig: UserConfig? { get set }
    @NeedleTailTransportActor
    var acknowledgment: Acknowledgment.AckType  { get set }
    @NeedleTailTransportActor
    var origin: String? { get }
    @NeedleTailTransportActor
    var target: String { get }
    @NeedleTailTransportActor
    var tags: [IRCTags]? { get }
    
    @NeedleTailClientActor
    func clientMessage(_
                       channel: Channel,
                       command: IRCCommand,
                       tags: [IRCTags]?
    ) async throws
    
    @NeedleTailTransportActor
    func transportMessage(_
                          channel: Channel,
                          type: TransportMessageType,
                          tags: [IRCTags]?
    ) async throws

    @BlobActor
    func blobMessage(_
                     channel: Channel,
                     command: IRCCommand,
                     tags: [IRCTags]?
    ) async throws
    
}

extension NeedleTailTransportDelegate {
    public var target: String { get { return "" } set{} }
    public var userConfig: UserConfig? { get { return nil } set{} }
    public var acknowledgment: Acknowledgment.AckType { get { return .none } set{} }

    public func clientMessage(_
                              channel: Channel,
                              command: IRCCommand,
                              tags: [IRCTags]? = nil
    ) async throws {
        let message = await IRCMessage(origin: self.origin, command: command, tags: tags)
        try await sendAndFlushMessage(channel, message: message)
    }
    
    public func transportMessage(_
                                 channel: Channel,
                                 type: TransportMessageType,
                                 tags: [IRCTags]? = nil
    ) async throws {
        var message: IRCMessage?
        switch type {
        case .standard(let command):
            message = IRCMessage(command: command, tags: tags)
        case .private(let command), .notice(let command):
            switch command {
            case .PRIVMSG(let recipients, let messageLines):
                let lines = messageLines.components(separatedBy: "\n")
                    .map { $0.replacingOccurrences(of: "\r", with: "") }
                _ = await lines.asyncMap {
                    message = await IRCMessage(origin: self.origin, command: .PRIVMSG(recipients, $0), tags: tags)
                }
            case .NOTICE(let recipients, let messageLines):
                let lines = messageLines.components(separatedBy: "\n")
                    .map { $0.replacingOccurrences(of: "\r", with: "") }
                _ = await lines.asyncMap {
                    message = await IRCMessage(origin: self.origin, command: .NOTICE(recipients, $0), tags: tags)
                }
            default:
                break
            }
        }
        guard let message = message else { return }
        try await sendAndFlushMessage(channel, message: message)
    }

    public func blobMessage(_
                            channel: Channel,
                            command: IRCCommand,
                            tags: [IRCTags]? = nil
    ) async throws {
        let message = IRCMessage(command: command, tags: tags)
        try await sendAndFlushMessage(channel, message: message)
    }
    
    public func sendAndFlushMessage(_ channel: Channel, message: IRCMessage) async throws {
        try await channel.writeAndFlush(message)
    }
}

public enum TransportMessageType: Sendable {
    case standard(IRCCommand)
    case `private`(IRCCommand)
    case notice(IRCCommand)
}
