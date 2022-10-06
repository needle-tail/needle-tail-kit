import CypherMessaging
import NeedleTailHelpers
import NIOCore

public protocol NeedleTailTransportDelegate: AnyObject {
    
    @NeedleTailTransportActor
    var channel: Channel { get set }
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
                       command: IRCCommand,
                       tags: [IRCTags]?
    ) async throws
    
    @NeedleTailTransportActor
    func transportMessage(_
                          type: TransportMessageType,
                          tags: [IRCTags]?
    ) async throws

    @BlobActor
    func blobMessage(_
                     command: IRCCommand,
                     tags: [IRCTags]?
    ) async throws
    
}

//MARK: Server/Client
extension NeedleTailTransportDelegate {
    public func sendAndFlushMessage(_ message: IRCMessage) async throws {
        print(message)
        try await channel.writeAndFlush(message)
    }
}

//MARK: Client Side
extension NeedleTailTransportDelegate {
    public var target: String { get { return "" } set{} }
    public var userConfig: UserConfig? { get { return nil } set{} }
    public var acknowledgment: Acknowledgment.AckType { get { return .none } set{} }

    public func clientMessage(_
                              command: IRCCommand,
                              tags: [IRCTags]? = nil
    ) async throws {
        let message = await IRCMessage(origin: self.origin, command: command, tags: tags)
        try await sendAndFlushMessage(message)
    }
    
    public func transportMessage(_
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
        try await sendAndFlushMessage(message)
    }

    public func blobMessage(_
                            command: IRCCommand,
                            tags: [IRCTags]? = nil
    ) async throws {
        let message = IRCMessage(command: command, tags: tags)
        try await sendAndFlushMessage(message)
    }
}

//MARK: Server Side
@NeedleTailTransportActor
extension NeedleTailTransportDelegate {
    
    public func sendError(
        _ code: IRCCommandCode,
        message: String? = nil,
        _ args: String...
    ) async throws {
        let enrichedArgs = args + [ message ?? code.errorMessage ]
        let message = IRCMessage(origin: origin,
                                 target: target,
                                 command: .numeric(code, enrichedArgs),
                                 tags: nil)
        try await sendAndFlushMessage(message)
    }
    
    public func sendReply(
        _ code: IRCCommandCode,
        _ args: String...
    ) async throws {
        let message = IRCMessage(origin: origin,
                                 target: target,
                                 command: .numeric(code, args),
                                 tags: nil)
        try await sendAndFlushMessage(message)
    }
    
    public func sendMotD(_ message: String) async throws {
        guard !message.isEmpty else { return }
        let origin = self.origin ?? "??"
        try await sendReply(.replyMotDStart, "- \(origin) Message of the Day -")
        
        let lines = message.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\r", with: "") }
            .map { "- " + $0 }
        
        _ = try await lines.asyncMap {
            let message = IRCMessage(origin: origin,
                                     command: .numeric(.replyMotD, [ target, $0 ]),
                                     tags: nil)
            try await sendAndFlushMessage(message)
        }
        try await sendReply(.replyEndOfMotD, "End of /MOTD command.")
    }
}

public enum TransportMessageType: Sendable {
    case standard(IRCCommand)
    case `private`(IRCCommand)
    case notice(IRCCommand)
}
