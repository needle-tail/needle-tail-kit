import NIO
import Logging
import Foundation
import NeedleTailHelpers


/// Basic syntax:
/// [':' SOURCE]? ' ' COMMAND [' ' ARGS]? [' :' LAST-ARG]?

public final class IRCChannelHandler: ChannelDuplexHandler {
    
    public typealias InboundIn   = ByteBuffer
    public typealias InboundOut  = IRCMessage
    
    public typealias OutboundIn  = IRCMessage
    public typealias OutboundOut = ByteBuffer
    var logger: Logger
    @NeedleTailTransportActor let consumer = ParseConsumer()
    var channel: Channel?
    public init(logger: Logger = Logger(label: "NeedleTailKit")) {
        self.logger = logger
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        self.logger.info("IRCChannelHandler is Active")
        context.fireChannelActive()
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        self.logger.info("IRCChannelHandler is Inactive")
        context.fireChannelInactive()
    }
    
    
    // MARK: - Reading
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.logger.trace("IRCChannelHandler Read")
        var buffer = self.unwrapInboundIn(data)
        let lines = buffer.readString(length: buffer.readableBytes) ?? ""
        guard !lines.isEmpty else { return }
        let messages = lines.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\r", with: "") }
            .filter{ $0 != ""}
        
        let future = mapMessages(context: context, messages: messages)
        future.whenComplete { switch $0 {
        case .success(let string):
            let message = self.asyncParse(context: context, line: string)
            message.whenComplete{ switch $0 {
            case .success(let message):
                self.channelRead(context: context, value: message)
            case .failure(let error):
                self.logger.error("AsyncParse Failed \(error)")
            }
            }
        case .failure(let error):
            self.logger.error("\(error)")
        }
        }
    }
    
    private func mapMessages(context: ChannelHandlerContext, messages: [String]) -> EventLoopFuture<String> {
        let promise = context.eventLoop.makePromise(of: String.self)
        _ = messages.compactMap { string in
            promise.succeed(string)
        }
        return promise.futureResult
    }
    
    private func asyncParse(context: ChannelHandlerContext, line: String) -> EventLoopFuture<IRCMessage> {
        let promise = context.eventLoop.makePromise(of: IRCMessage.self)
        promise.completeWithTask {
            
            guard let message = await self.processMessage(line) else {
                return try await promise.futureResult.get()
            }
            return message
        }
        return promise.futureResult
    }
    
    let parser = MessageParser()
    
    @ParsingActor
    public func processMessage(_ message: String) async -> IRCMessage? {
        consumer.feedConsumer(message)
        
        do {
            for try await result in ParserSequence(consumer: consumer) {
                switch result {
                case.success(let message):
                    return try await IRCTaskHelpers.parseMessageTask(task: message, messageParser: parser)
                case .finished:
                    return nil
                }
            }
        } catch {
            logger.error("Parser Sequence Error: \(error)")
        }
        return nil
    }
    
    public func channelReadComplete(context: ChannelHandlerContext) {
        self.logger.trace("READ Complete")
    }
    
    public func channelRead(context: ChannelHandlerContext, value: InboundOut) {
        context.fireChannelRead(self.wrapInboundOut(value))
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Swift.Error) {
        context.fireErrorCaught(MessageParserError.transportError(error))
    }
    
//    public func write(
//        context: ChannelHandlerContext,
//        data: NIOAny,
//        promise: EventLoopPromise<Void>?
//    ) {
//        let message: OutboundIn = self.unwrapOutboundIn(data)
//        write(context: context, value: message, promise: promise)
//    }
//    
//    public final func write(
//        context: ChannelHandlerContext,
//        value: IRCMessage,
//        promise: EventLoopPromise<Void>?
//    ) {
//        var buffer = context.channel.allocator.buffer(capacity: 200)
//        encode(value: value, target: value.target, into: &buffer)
//        context.write(NIOAny(buffer), promise: promise)
//    }
}
