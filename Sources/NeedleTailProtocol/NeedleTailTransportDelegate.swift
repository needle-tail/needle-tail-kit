import CypherMessaging
import NeedleTailHelpers
@_spi(AsyncChannel) import NIOCore

@NeedleTailClientActor
public protocol NeedleTailClientDelegate: AnyObject {
    var channel: Channel { get set }
}

public protocol NeedleTailTransportDelegate: AnyObject, NeedleTailClientDelegate {
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
    
    @PingPongActor
    func pingPongMessage(_
                         command: IRCCommand,
                         tags: [IRCTags]?
    ) async throws
    
}

//MARK: Server/Client
extension NeedleTailTransportDelegate {
    
    public func sendAndFlushMessage(_ message: IRCMessage) async throws {
        let buffer = await NeedleTailEncoder.encode(value: message)
        try await channel.writeAndFlush(buffer)
    }
}

//MARK: Client Side
extension NeedleTailTransportDelegate {
    public var target: String { get { return "" } set{} }
    public var userConfig: UserConfig? { get { return nil } set{} }
    
    @NeedleTailClientActor
    public func clientMessage(_
                              command: IRCCommand,
                              tags: [IRCTags]? = nil
    ) async throws {
        let message = await IRCMessage(origin: self.origin, command: command, tags: tags)
        try await sendAndFlushMessage(message)
    }
    
    @NeedleTailTransportActor
    public func transportMessage(_
                                 type: TransportMessageType,
                                 tags: [IRCTags]? = nil
    ) async throws {
        switch type {
        case .standard(let command):
            let message = IRCMessage(command: command, tags: tags)
            try await sendAndFlushMessage(message)
        case .private(let command), .notice(let command):
            switch command {
            case .PRIVMSG(let recipients, let messageLines):
                let lines = messageLines.components(separatedBy: Constants.cLF.rawValue)
                    .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
                _ = try await lines.asyncMap {
                    let message = IRCMessage(origin: self.origin, command: .PRIVMSG(recipients, $0), tags: tags)
                    try await sendAndFlushMessage(message)
                }
                
            case .NOTICE(let recipients, let messageLines):
                let lines = messageLines.components(separatedBy: Constants.cLF.rawValue)
                    .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
                _ = try await lines.asyncMap {
                    let message = IRCMessage(origin: self.origin, command: .NOTICE(recipients, $0), tags: tags)
                    try await sendAndFlushMessage(message)
                }
            default:
                break
            }
        }
    }
    
    @BlobActor
    public func blobMessage(_
                            command: IRCCommand,
                            tags: [IRCTags]? = nil
    ) async throws {
        let message = IRCMessage(command: command, tags: tags)
        try await sendAndFlushMessage(message)
    }
    
    @PingPongActor
    public func pingPongMessage(_
                                command: IRCCommand,
                                tags: [IRCTags]?
    ) async throws {
        let message = IRCMessage(command: command, tags: tags)
        try await sendAndFlushMessage(message)
    }
    
    @MultipartActor
    public func multipartMessage(_
                                 command: IRCCommand,
                                 tags: [IRCTags]?
    ) async throws {
        print("MULTIPART___")
        let message = IRCMessage(command: command, tags: tags)
        try await sendAndFlushMessage(message)
    }
}

//MARK: Server Side
extension NeedleTailTransportDelegate {
    
    @NeedleTailTransportActor
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
    
    @NeedleTailTransportActor
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
    
    @NeedleTailTransportActor
    public func sendMotD(_ message: String) async throws {
        guard !message.isEmpty else { return }
        let origin = self.origin ?? "??"
        try await sendReply(.replyMotDStart, "- Message of the Day -")
        
        let lines = message.components(separatedBy: Constants.cLF.rawValue)
            .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
            .map { Constants.minus.rawValue + Constants.space.rawValue + $0 }
        
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

