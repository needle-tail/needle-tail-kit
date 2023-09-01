import CypherMessaging
import NeedleTailHelpers
@_spi(AsyncChannel) import NIOCore

public protocol NeedleTailClientDelegate: AnyObject, IRCDispatcher, NeedleTailWriterDelegate {
    
    @_spi(AsyncChannel)
    func transportMessage(_
                          writer: NIOAsyncChannelOutboundWriter<ByteBuffer>,
                          origin: String,
                          type: TransportMessageType,
                          tags: [IRCTags]?
    ) async throws
}

public protocol NeedleTailWriterDelegate: AnyObject {
    @_spi(AsyncChannel)
    func sendAndFlushMessage(_
                             writer: NIOAsyncChannelOutboundWriter<ByteBuffer>,
                             message: IRCMessage
    ) async throws
}

//TODO: Fa Fu: Getting fat/rich
extension NeedleTailWriterDelegate {
    @_spi(AsyncChannel)
    public func sendAndFlushMessage(_
                                    writer: NIOAsyncChannelOutboundWriter<ByteBuffer>,
                                    message: IRCMessage
    ) async throws {
        let buffer = await NeedleTailEncoder.encode(value: message)
        try await writer.write(buffer)
    }
}

//MARK: Client Side
extension NeedleTailClientDelegate {
    @_spi(AsyncChannel)
    public func transportMessage(_
                                 writer: NIOAsyncChannelOutboundWriter<ByteBuffer>,
                                 origin: String = "",
                                 type: TransportMessageType,
                                 tags: [IRCTags]? = nil
    ) async throws {
        switch type {
        case .standard(let command):
            let message = IRCMessage(origin: origin, command: command, tags: tags)
            try await sendAndFlushMessage(writer, message: message)
        case .private(let command), .notice(let command):
            switch command {
            case .PRIVMSG(let recipients, let messageLines):
                let lines = messageLines.components(separatedBy: Constants.cLF.rawValue)
                    .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
                _ = try await lines.asyncMap {
                    let message = IRCMessage(origin: origin, command: .PRIVMSG(recipients, $0), tags: tags)
                    try await sendAndFlushMessage(writer, message: message)
                }
                
            case .NOTICE(let recipients, let messageLines):
                let lines = messageLines.components(separatedBy: Constants.cLF.rawValue)
                    .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
                _ = try await lines.asyncMap {
                    let message = IRCMessage(origin: origin, command: .NOTICE(recipients, $0), tags: tags)
                    try await sendAndFlushMessage(writer, message: message)
                }
            default:
                break
            }
        }
    }
}

//MARK: Server Side
public protocol NeedleTailServerMessageDelegate: AnyObject, IRCDispatcher, NeedleTailWriterDelegate {}

extension NeedleTailServerMessageDelegate {
    
    @_spi(AsyncChannel)
    public func sendAndFlushMessage(_
                                    writer: NIOAsyncChannelOutboundWriter<ByteBuffer>,
                                    message: IRCMessage
    ) async throws {
        let buffer = await NeedleTailEncoder.encode(value: message)
        try await writer.write(buffer)
    }
    
    @_spi(AsyncChannel)
    public func sendError(_
                          writer: NIOAsyncChannelOutboundWriter<ByteBuffer>,
                          origin: String,
                          target: String,
                          code: IRCCommandCode,
                          message: String? = nil,
                          args: String...
    ) async throws {
        let enrichedArgs = args + [ message ?? code.errorMessage ]
        let message = IRCMessage(origin: origin,
                                 target: target,
                                 command: .numeric(code, enrichedArgs),
                                 tags: nil)
        try await sendAndFlushMessage(writer, message: message)
    }
    
    @_spi(AsyncChannel)
    public func sendReply(_
                          writer: NIOAsyncChannelOutboundWriter<ByteBuffer>,
                          origin: String,
                          target: String,
                          code: IRCCommandCode,
                          args: String...
    ) async throws {
        let message = IRCMessage(origin: origin,
                                 target: target,
                                 command: .numeric(code, args),
                                 tags: nil)
        try await sendAndFlushMessage(writer, message: message)
    }
    
    @_spi(AsyncChannel)
    public func sendMotD(_
                         writer: NIOAsyncChannelOutboundWriter<ByteBuffer>,
                         origin: String,
                         target: String,
                         message: String
    ) async throws {
        guard !message.isEmpty else { return }
        let origin = origin
        try await sendReply(
            writer,
            origin: origin,
            target: target,
            code: .replyMotDStart,
            args: "- Message of the Day -"
        )
        
        let lines = message.components(separatedBy: Constants.cLF.rawValue)
            .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
            .map { Constants.minus.rawValue + Constants.space.rawValue + $0 }
        
        _ = try await lines.asyncMap {
            let message = IRCMessage(origin: origin,
                                     command: .numeric(.replyMotD, [ target, $0 ]),
                                     tags: nil)
            try await sendAndFlushMessage(writer, message: message)
        }
        try await sendReply(
            writer,
            origin: origin,
            target: target,
            code: .replyEndOfMotD,
            args:"End of /MOTD command."
        )
    }
}

public enum TransportMessageType: Sendable {
    case standard(IRCCommand)
    case `private`(IRCCommand)
    case notice(IRCCommand)
}

