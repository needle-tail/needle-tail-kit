import NIOCore
import Logging
import Foundation
import NeedleTailHelpers
import NIOConcurrencyHelpers
import NIOSSL

/// Basic syntax:
/// [':' SOURCE]? ' ' COMMAND [' ' ARGS]? [' :' LAST-ARG]?

//public final class IRCChannelHandler: ChannelDuplexHandler {
//    
//    
//    public typealias InboundIn   = ByteBuffer
//    public typealias InboundOut  = IRCMessage
//    public typealias OutboundIn  = IRCMessage
//    public typealias OutboundOut = ByteBuffer
//    
//    let logger: Logger
//    var channel: Channel?
//    var sslServerHandler: NIOSSLServerHandler?
//    @ParsingActor let consumer = ParseConsumer()
//    @ParsingActor var monitor: ChannelMonitor?
//    
//    
//    public init(
//        logger: Logger = Logger(label: "NeedleTailKit"),
//        sslServerHandler: NIOSSLServerHandler? = nil
//    ) {
//        self.logger = logger
//        self.sslServerHandler = sslServerHandler
//        Task {
//            await initializeMonitor()
//        }
//    }
//    
//    @ParsingActor
//    private func initializeMonitor() async {
//        self.monitor = ChannelMonitor(consumer: consumer)
//    }
//    
//    public func channelActive(context: ChannelHandlerContext) {
//        self.logger.info("IRCChannelHandler is Active")
//        context.fireChannelActive()
//    }
//    
//    public func channelInactive(context: ChannelHandlerContext) {
//        self.logger.trace("IRCChannelHandler is Inactive")
//        context.fireChannelInactive()
//    }
//    
//    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
//        self.logger.trace("IRCChannelHandler Read")
//        var buffer = self.unwrapInboundIn(data)
//        guard let lines = buffer.readString(length: buffer.readableBytes) else { return }
//        print("LINES_____", lines)
//        guard !lines.isEmpty else { return }
//        let messages = lines.components(separatedBy: "\n")
//            .map { $0.replacingOccurrences(of: "\r", with: "") }
//            .filter{ $0 != ""}
//        
//        context.eventLoop.executeAsync {
//            await self.consumer.feedConsumer(messages)
//            await self.monitor?.monitorQueue()
//            
//            return try await self.feedAndDrain({ monitor in
//                return await monitor?.stack
//            }, { monitor in
//                if consumptionState == .ready {
//                    await self.drain(monitor)
//                }
//            })
//        }
//        .whenComplete{  switch $0 {
//        case .success(let stack):
//            var stack = stack
//            if !stack.isEmpty() {
//                for _ in stack.enqueueStack {
//                    if stack.peek() != nil {
//                        guard let message = stack.dequeue() else { return }
//                        self.channelRead(context: context, value: message)
//                    }
//                }
//            }
//            
//        case .failure(let error):
//            self.logger.error("\(error)")
//            
//        }}
//    }
//    
//    @ParsingActor
//    private func drain(_ monitor: ChannelMonitor?) {
//        monitor?.stack.drain()
//    }
//    
//    @ParsingActor
//    private func feedAndDrain(
//        _ feed: @Sendable @escaping (_ monitor: ChannelMonitor?) async -> SyncStack<IRCMessage>?,
//        _ drain: @Sendable @escaping (_ monitor: ChannelMonitor?) async -> Void
//    ) async throws -> SyncStack<IRCMessage> {
//        guard let monitor = self.monitor else { throw NeedleTailError.channelMonitorIsNil }
//        guard let mon = await feed(monitor) else { throw NeedleTailError.channelMonitorIsNil }
//        _ = await drain(monitor)
//        return mon
//    }
//    
//    private func channelRead(context: ChannelHandlerContext, value: InboundOut) {
//        let wioValue = wrapInboundOut(value)
//        context.fireChannelRead(wioValue)
//    }
//    
//    public func errorCaught(context: ChannelHandlerContext, error: Swift.Error) {
//        let error = MessageParserError.transportError(error)
//        if sslServerHandler != nil {
//            logger.error("Parsing Error is: \(error)")
//            let promise = context.eventLoop.makePromise(of: Void.self)
//            self.sslServerHandler?.stopTLS(promise: promise)
//        }
//        context.fireErrorCaught(error)
//    }
//    
//    public func encodeMessage(channel: Channel, value: IRCMessage) async -> ByteBuffer {
//        await self.encode(value: value, target: value.target, channel: channel)
//    }
//    
//    public func write(
//        context: ChannelHandlerContext,
//        data: NIOAny,
//        promise: EventLoopPromise<Void>?
//    ) {
//        let channel = context.channel
//        let message = self.unwrapOutboundIn(data)
//        let buffer: EventLoopFuture<ByteBuffer> = context.eventLoop.executeAsync {
//           return await self.encodeMessage(channel: channel, value: message)
//        }
//            buffer.whenComplete { switch $0 {
//        case .success(let buffer):
//            context.writeAndFlush(NIOAny(buffer), promise: promise)
//        case .failure(let error):
//            self.logger.error("\(error)")
//        }
//        }
//    }
//}


//@ParsingActor
//final class ChannelMonitor {
//
//    private let logger = Logger(label: "ChannelMonitor")
//    private let consumer: ParseConsumer
//    private var hasStarted = false
//    private let parser = MessageParser()
//    var stack = SyncStack<IRCMessage>()
//
//    init(consumer: ParseConsumer) {
//        self.consumer = consumer
//        Task {
//            await monitorQueue()
//        }
//    }
//
//    func monitorQueue() async {
//
//        func checkProcess() async  {
//            if consumer.count >= 1 {
//                await processMessage()
//            } else {
//                return
//            }
//        }
//
//        await checkProcess()
//
//        return
//    }
//
//    // We process our Message twice before we consume it
//    private func processMessage() async {
//        do {
//            for try await result in ParserSequence(consumer: consumer) {
//                switch result {
//                case.success(let msg):
//                    let parsedMessage = try await AsyncMessageTask.parseMessageTask(task: msg, messageParser: parser)
//                    if !stack.enqueueStack.contains(parsedMessage) {
//                        stack.enqueue(parsedMessage)
//                    }
//                case .finished:
//                    return
//                }
//            }
//        } catch {
//            logger.error("\(error)")
//        }
//    }
//}


public final class AsyncMessageChannelHandler: ChannelDuplexHandler {
    public typealias InboundIn   = ByteBuffer
    public typealias InboundOut  = IRCMessage
    public typealias OutboundIn  = IRCMessage
    public typealias OutboundOut = ByteBuffer
    
    let logger: Logger
    var channel: Channel?
    var sslServerHandler: NIOSSLServerHandler?
    @ParsingActor private let parser = MessageParser()
    private var backPressureStrategy: MockNIOElementStreamBackPressureStrategy!
    private var delegate: MockNIOBackPressuredStreamSourceDelegate!
    private var sequence: NIOThrowingAsyncSequenceProducer<
        String,
        Error,
        MockNIOElementStreamBackPressureStrategy,
        MockNIOBackPressuredStreamSourceDelegate
    >!
    private var source: NIOThrowingAsyncSequenceProducer<
        String,
        Error,
        MockNIOElementStreamBackPressureStrategy,
        MockNIOBackPressuredStreamSourceDelegate
    >.Source!
    
    
    private var writer: NIOAsyncWriter<IRCMessage, MockAsyncWriterDelegate>!
    private var sink: NIOAsyncWriter<IRCMessage, MockAsyncWriterDelegate>.Sink!
    private var writerDelegate: MockAsyncWriterDelegate!
    private var iterator: NIOThrowingAsyncSequenceProducer<String, Error, MockNIOElementStreamBackPressureStrategy, MockNIOBackPressuredStreamSourceDelegate>.AsyncIterator?
    
    public init(
        logger: Logger = Logger(label: "NeedleTailKit"),
        sslServerHandler: NIOSSLServerHandler? = nil
    ) {
        self.logger = logger
        self.sslServerHandler = sslServerHandler
        
        self.backPressureStrategy = .init()
        self.delegate = .init()
        let result = NIOThrowingAsyncSequenceProducer.makeSequence(
            elementType: String.self,
            failureType: Error.self,
            backPressureStrategy: self.backPressureStrategy,
            delegate: self.delegate
        )
        self.source = result.source
        self.sequence = result.sequence
        
        
        self.writerDelegate = .init()
        let newWriter = NIOAsyncWriter.makeWriter(
            elementType: IRCMessage.self,
            isWritable: true,
            delegate: self.writerDelegate
        )
        self.writer = newWriter.writer
        self.sink = newWriter.sink
        Task {
            self.iterator = self.sequence?.makeAsyncIterator()
        }
    }
    
    deinit {
        self.backPressureStrategy = nil
        self.delegate = nil
        self.sequence = nil
        self.writerDelegate = nil
        self.writer = nil
        self.sink = nil
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        self.logger.info("AsyncMessageChannelHandler is Active")
        context.fireChannelActive()
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        self.logger.trace("AsyncMessageChannelHandler is Inactive")
        context.fireChannelInactive()
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.logger.info("AsyncMessageChannelHandler Read")
        var buffer = self.unwrapInboundIn(data)
        guard let lines = buffer.readString(length: buffer.readableBytes) else { return }

        guard !lines.isEmpty else { return }
        let messages = lines.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\r", with: "") }
            .filter{ $0 != ""}
        _ = self.source.yield(contentsOf: messages)

        _ = context.eventLoop.executeAsync {
            func runIterator() async throws {
                guard let result = try await self.iterator?.next() else { throw NeedleTailError.parsingError }
                let parsedMessage = try await AsyncMessageTask.parseMessageTask(task: result, messageParser: self.parser)
                try await self.writer.yield(parsedMessage)
            }

            try await runIterator()
            if self.delegate.produceMoreCallCount != 0 {
               try await runIterator()
            }
        }
        channelRead(context: context)
    }
    
    private func channelRead(context: ChannelHandlerContext) {
        let promise = context.eventLoop.makePromise(of: Deque<IRCMessage>.self)
        self.writerDelegate.didYieldHandler = { deq in
            promise.succeed(deq)
        }
        promise.futureResult.whenSuccess { messages in
            for message in messages {
                let wioValue = self.wrapInboundOut(message)
                context.fireChannelRead(wioValue)
            }
        }
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
        let buffer: EventLoopFuture<ByteBuffer> = context.eventLoop.executeAsync {
           return await self.encodeMessage(channel: channel, value: message)
        }
            buffer.whenComplete { switch $0 {
        case .success(let buffer):
            context.writeAndFlush(NIOAny(buffer), promise: promise)
        case .failure(let error):
            self.logger.error("\(error)")
        }
        }
    }
}

final class MockNIOElementStreamBackPressureStrategy: NIOAsyncSequenceProducerBackPressureStrategy, @unchecked Sendable {
    var didYieldCallCount = 0
    var didYieldHandler: ((Int) -> Bool)?
    func didYield(bufferDepth: Int) -> Bool {
        self.didYieldCallCount += 1
        if let didYieldHandler = self.didYieldHandler {
            return didYieldHandler(bufferDepth)
        }
        return false
    }

    var didNextCallCount = 0
    var didNextHandler: ((Int) -> Bool)?
    func didConsume(bufferDepth: Int) -> Bool {
        self.didNextCallCount += 1
        if let didNextHandler = self.didNextHandler {
            return didNextHandler(bufferDepth)
        }
        return false
    }
}

final class MockNIOBackPressuredStreamSourceDelegate: NIOAsyncSequenceProducerDelegate, @unchecked Sendable {
    var produceMoreCallCount = 0
    var produceMoreHandler: (() -> Void)?
    func produceMore() {
        self.produceMoreCallCount += 1
        if let produceMoreHandler = self.produceMoreHandler {
            return produceMoreHandler()
        }
    }

    var didTerminateCallCount = 0
    var didTerminateHandler: (() -> Void)?
    func didTerminate() {
        self.didTerminateCallCount += 1
        if let didTerminateHandler = self.didTerminateHandler {
            return didTerminateHandler()
        }
    }
}

import DequeModule
private final class MockAsyncWriterDelegate: NIOAsyncWriterSinkDelegate, @unchecked Sendable {
    typealias Element = IRCMessage

    var didYieldCallCount = 0
    var didYieldHandler: ((Deque<IRCMessage>) -> Void)?
    func didYield(contentsOf sequence: Deque<IRCMessage>) {
        self.didYieldCallCount += 1
        if let didYieldHandler = self.didYieldHandler {
            didYieldHandler(sequence)
        }
    }

    var didTerminateCallCount = 0
    var didTerminateHandler: ((Error?) -> Void)?
    func didTerminate(error: Error?) {
        self.didTerminateCallCount += 1
        if let didTerminateHandler = self.didTerminateHandler {
            didTerminateHandler(error)
        }
    }
}
