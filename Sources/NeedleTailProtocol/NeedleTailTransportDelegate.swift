import CypherMessaging
import NeedleTailHelpers

@NeedleTailClientActor
public protocol NeedleTailClientDelegate: AnyObject {
    var channel: NIOAsyncChannel<ByteBuffer, ByteBuffer> { get set }
}
@NeedleTailTransportActor
public protocol NeedleTailTransportDelegate: AnyObject, NeedleTailClientDelegate {
    var origin: String? { get }
    var target: String { get }
    var tags: [IRCTags]? { get }
    
    func clientMessage(_
                       command: IRCCommand,
                       tags: [IRCTags]?
    ) async throws
    
    func transportMessage(_
                          type: TransportMessageType,
                          tags: [IRCTags]?
    ) async throws

    func blobMessage(_
                     command: IRCCommand,
                     tags: [IRCTags]?
    ) async throws
    
}

//MARK: Server/Client
extension NeedleTailTransportDelegate {
    
    public func sendAndFlushMessage(_ message: IRCMessage) async throws {
        //THIS IS ANNOYING BUT WORKS
        try await RunLoop.run(5, sleep: 1, stopRunning: {
            var canRun = true
            if await self.channel.channel.isActive  {
                canRun = false
            }
            return canRun
        })
        let buffer = await NeedleTailEncoder.encode(value: message)
        try await channel.writeAndFlush(buffer)
    }
}

//MARK: Client Side
extension NeedleTailTransportDelegate {
    public var target: String { get { return "" } set{} }
    public var userConfig: UserConfig? { get { return nil } set{} }
//    public var acknowledgment: Acknowledgment.AckType { get { return .none } set{} }

    public func clientMessage(_
                              command: IRCCommand,
                              tags: [IRCTags]? = nil
    ) async throws {
        let message = IRCMessage(origin: self.origin, command: command, tags: tags)
        try await sendAndFlushMessage(message)
    }
    
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
                let lines = messageLines.components(separatedBy: Constants.cLF)
                    .map { $0.replacingOccurrences(of: Constants.cCR, with: Constants.space) }
                _ = try await lines.asyncMap {
                   let message = IRCMessage(origin: self.origin, command: .PRIVMSG(recipients, $0), tags: tags)
                    try await sendAndFlushMessage(message)
                }
                
            case .NOTICE(let recipients, let messageLines):
                let lines = messageLines.components(separatedBy: Constants.cLF)
                    .map { $0.replacingOccurrences(of: Constants.cCR, with: Constants.space) }
                _ = try await lines.asyncMap {
                    let message = IRCMessage(origin: self.origin, command: .NOTICE(recipients, $0), tags: tags)
                    try await sendAndFlushMessage(message)
                }
            default:
                break
            }
        }
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
        try await sendReply(.replyMotDStart, "\(origin) - Message of the Day -")
        
        let lines = message.components(separatedBy: Constants.cLF)
            .map { $0.replacingOccurrences(of: Constants.cCR, with: Constants.space) }
            .map { Constants.minus + Constants.space + $0 }
        
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

