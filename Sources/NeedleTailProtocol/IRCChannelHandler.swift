import NIOCore
import Logging
import Foundation
import NeedleTailHelpers
import NIOConcurrencyHelpers
import NIOSSL

/// Basic syntax:
/// [':' SOURCE]? ' ' COMMAND [' ' ARGS]? [' :' LAST-ARG]?

public final class IRCChannelHandler: ChannelDuplexHandler {
    
    public typealias InboundIn   = ByteBuffer
    public typealias InboundOut  = IRCMessage
    public typealias OutboundIn  = IRCMessage
    public typealias OutboundOut = ByteBuffer
    
    let logger: Logger
    var channel: Channel?
    var sslServerHandler: NIOSSLServerHandler?
    @ParsingActor let consumer = ParseConsumer()
    @ParsingActor var monitor: ChannelMonitor?
    
    
    public init(
        logger: Logger = Logger(label: "NeedleTailKit"),
        sslServerHandler: NIOSSLServerHandler? = nil
    ) {
        self.logger = logger
        self.sslServerHandler = sslServerHandler
        Task {
            await initializeMonitor()
        }
    }
    
    @ParsingActor
    private func initializeMonitor() async {
        self.monitor =  ChannelMonitor(consumer: consumer)
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        self.logger.info("IRCChannelHandler is Active")
        context.fireChannelActive()
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        self.logger.trace("IRCChannelHandler is Inactive")
        context.fireChannelInactive()
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.logger.trace("IRCChannelHandler Read")
        var buffer = self.unwrapInboundIn(data)
        let lines = buffer.readString(length: buffer.readableBytes) ?? ""
        guard !lines.isEmpty else { return }
        let messages = lines.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\r", with: "") }
            .filter{ $0 != ""}
        
        context.eventLoop.executeAsync {
            await self.consumer.feedConsumer(messages)
            await self.monitor?.monitorQueue()
            
            return try await self.feedAndDrain({ monitor in
                return await monitor?.stack
            }, { monitor in
                if consumptionState == .ready {
                    await self.drain(monitor)
                }
            })
        }
        .whenComplete{  switch $0 {
        case .success(let stack):
            var stack = stack
            if !stack.isEmpty() {
                for _ in stack.enqueueStack {
                    if stack.peek() != nil {
                        guard let message = stack.dequeue() else { return }
                        self.channelRead(context: context, value: message)
                    }
                }
            }
            
        case .failure(let error):
            logger.error("\(error)")
            
        }}
    }
    
    @ParsingActor
    private func drain(_ monitor: ChannelMonitor?) {
        monitor?.stack.drain()
    }
    
    @ParsingActor
    private func feedAndDrain(
        _ feed: @Sendable @escaping (_ monitor: ChannelMonitor?) async -> SyncStack<IRCMessage>?,
        _ drain: @Sendable @escaping (_ monitor: ChannelMonitor?) async -> Void
    ) async throws -> SyncStack<IRCMessage> {
        guard let monitor = self.monitor else { throw NeedleTailError.channelMonitorIsNil }
        guard let mon = await feed(monitor) else { throw NeedleTailError.channelMonitorIsNil }
        _ = await drain(monitor)
        return mon
    }
    
    public func channelRead(context: ChannelHandlerContext, value: InboundOut) {
        let wioValue = wrapInboundOut(value)
        context.fireChannelRead(wioValue)
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Swift.Error) {
        let error = MessageParserError.transportError(error)
        if sslServerHandler != nil {
            logger.error("Parsing Error is: \(error)")
            let promise = context.eventLoop.makePromise(of: Void.self)
            self.sslServerHandler?.stopTLS(promise: promise)
        }
        context.fireErrorCaught(error)
    }
    
    public func encodeMessage(channel: Channel, value: IRCMessage) async -> ByteBuffer {
        await self.encode(value: value, target: value.target, channel: channel)
    }
    
    public func write(
        context: ChannelHandlerContext,
        data: NIOAny,
        promise: EventLoopPromise<Void>?
    ) {
        let channel = context.channel
        let message = self.unwrapOutboundIn(data)
        context.eventLoop.executeAsync {
            await self.encodeMessage(channel: channel, value: message)
        }.whenComplete { switch $0 {
        case .success(let buffer):
            context.writeAndFlush(NIOAny(buffer), promise: promise)
        case .failure(let error):
            self.logger.error("\(error)")
        }
        }
    }
}


@ParsingActor
final class ChannelMonitor {
    
    private let logger = Logger(label: "ChannelMonitor")
    private let consumer: ParseConsumer
    private var hasStarted = false
    private let parser = MessageParser()
    var stack = SyncStack<IRCMessage>()
    
    init(consumer: ParseConsumer) {
        self.consumer = consumer
        Task {
            await monitorQueue()
        }
    }
    
    func monitorQueue() async {
        
        func checkProcess() async  {
            if consumer.count >= 1 {
                await processMessage()
            } else {
                return
            }
        }
        
        await checkProcess()
        
        return
    }
    
    // We process our Message twice before we consume it
    private func processMessage() async {
        do {
            for try await result in ParserSequence(consumer: consumer) {
                switch result {
                case.success(let msg):
                    let parsedMessage = try await IRCTaskHelpers.parseMessageTask(task: msg, messageParser: parser)
                    if !stack.enqueueStack.contains(parsedMessage) {
                        stack.enqueue(parsedMessage)
                    }
                case .finished:
                    return
                }
            }
        } catch {
            logger.error("\(error)")
        }
    }
}
