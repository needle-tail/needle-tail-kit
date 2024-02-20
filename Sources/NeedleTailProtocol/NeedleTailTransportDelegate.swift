import CypherMessaging
import NeedleTailHelpers
 import NIOCore

public protocol NeedleTailClientDelegate: AnyObject, IRCDispatcher, NeedleTailWriterDelegate {
    
    
    func transportMessage(_
                          writer: NIOAsyncChannelOutboundWriter<ByteBuffer>,
                          origin: String,
                          command: IRCCommand,
                          tags: [IRCTags]?
    ) async throws
}

public protocol NeedleTailWriterDelegate: AnyObject {
    
    func sendAndFlushMessage(_
                             writer: NIOAsyncChannelOutboundWriter<ByteBuffer>,
                             message: IRCMessage
    ) async throws
}

//TODO: Fa Fu: Getting fat/rich
extension NeedleTailWriterDelegate {
    
    public func sendAndFlushMessage(_
                                    writer: NIOAsyncChannelOutboundWriter<ByteBuffer>,
                                    message: IRCMessage
    ) async throws {
        do {
            let buffer = await NeedleTailEncoder.encode(value: message)
            try await writer.write(buffer)
        } catch {
            throw error
        }
    }
}

//MARK: Client Side
extension NeedleTailClientDelegate {
    
    public func transportMessage(_
                                 writer: NIOAsyncChannelOutboundWriter<ByteBuffer>,
                                 origin: String = "",
                                 command: IRCCommand,
                                 tags: [IRCTags]? = nil
    ) async throws {
            switch command {
            case .PRIVMSG(let recipients, let messageLines):
                let lines = messageLines.components(separatedBy: Constants.cLF.rawValue)
                    .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
                _ = try await lines.asyncMap {
                    let message = IRCMessage(origin: origin, command: .PRIVMSG(recipients, $0), tags: tags)
                    try await sendAndFlushMessage(writer, message: message)
                }
            case .ISON(let nicks):
                let message = IRCMessage(origin: origin, command: .ISON(nicks), tags: tags)
                try await sendAndFlushMessage(writer, message: message)
            case .NOTICE(let recipients, let messageLines):
                let lines = messageLines.components(separatedBy: Constants.cLF.rawValue)
                    .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
                _ = try await lines.asyncMap {
                    let message = IRCMessage(origin: origin, command: .NOTICE(recipients, $0), tags: tags)
                    try await sendAndFlushMessage(writer, message: message)
                }
            default:
                let message = IRCMessage(origin: origin, command: command, tags: tags)
                try await sendAndFlushMessage(writer, message: message)
        }
    }
}

//MARK: Server Side
public protocol NeedleTailServerMessageDelegate: AnyObject, IRCDispatcher, NeedleTailWriterDelegate {}

extension NeedleTailServerMessageDelegate {
    
    
    public func sendAndFlushMessage(_
                                    writer: NIOAsyncChannelOutboundWriter<ByteBuffer>,
                                    message: IRCMessage
    ) async throws {
        let buffer = await NeedleTailEncoder.encode(value: message)
        try await writer.write(buffer)
    }
    
    
    public func sendError(_
                          writer: NIOAsyncChannelOutboundWriter<ByteBuffer>,
                          origin: String,
                          target: String,
                          code: IRCCommandCode,
                          message: String? = nil,
                          args: [String] = []
    ) async throws {
        let enrichedArgs = args + [ message ?? code.errorMessage ]
        let message = IRCMessage(origin: origin,
                                 target: target,
                                 command: .numeric(code, enrichedArgs),
                                 tags: nil)
        try await sendAndFlushMessage(writer, message: message)
    }
    
    
    public func sendReply(_
                          writer: NIOAsyncChannelOutboundWriter<ByteBuffer>,
                          origin: String,
                          target: String,
                          code: IRCCommandCode,
                          args: [String]
    ) async throws {
        let message = IRCMessage(origin: origin,
                                 target: target,
                                 command: .numeric(code, args),
                                 tags: nil)
        try await sendAndFlushMessage(writer, message: message)
    }
    
    
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
            args: ["- Message of the Day -"]
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
            args: ["End of /MOTD command."]
        )
    }
}
