//import NIOCore
//import Logging
//import Foundation
//import NeedleTailHelpers
//import NIOConcurrencyHelpers
//import NIOSSL
//import DequeModule
//
///// Basic syntax:
///// [':' SOURCE]? ' ' COMMAND [' ' ARGS]? [' :' LAST-ARG]?
//
//public final class AsyncMessageChannelHandler: ChannelDuplexHandler {
//    public typealias InboundIn   = ByteBuffer
//    public typealias InboundOut  = IRCMessage
//    public typealias OutboundIn  = IRCMessage
//    public typealias OutboundOut = ByteBuffer
//    
//    let logger: Logger
//    var channel: Channel?
//    var sslServerHandler: NIOSSLServerHandler?
//    @ParsingActor private let parser = MessageParser()
//    private var backPressureStrategy: NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark!
//    private var delegate: NIOBackPressuredStreamSourceDelegate!
//    private var sequence: NIOThrowingAsyncSequenceProducer<
//        ByteBuffer,
//        Error,
//        NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
//        NIOBackPressuredStreamSourceDelegate
//    >!
//    private var source: NIOThrowingAsyncSequenceProducer<
//        ByteBuffer,
//        Error,
//        NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
//        NIOBackPressuredStreamSourceDelegate
//    >.Source!
//    
//    
//    private var bufferDeque = Deque<ByteBuffer>()
//    private var writer: NIOAsyncWriter<IRCMessage, AsyncWriterDelegate>!
//    private var sink: NIOAsyncWriter<IRCMessage, AsyncWriterDelegate>.Sink!
//    private var writerDelegate: AsyncWriterDelegate!
//    private var iterator: NIOThrowingAsyncSequenceProducer<
//        ByteBuffer,
//        Error,
//        NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
//        NIOBackPressuredStreamSourceDelegate>.AsyncIterator?
//    
//    public init(
//        logger: Logger = Logger(label: "NeedleTailKit"),
//        sslServerHandler: NIOSSLServerHandler? = nil
//    ) {
//        self.logger = logger
//        self.sslServerHandler = sslServerHandler
//        
//        self.backPressureStrategy = NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark(lowWatermark: 5, highWatermark: 10)
//        self.delegate = .init()
//        let result = NIOThrowingAsyncSequenceProducer.makeSequence(
//            elementType: ByteBuffer.self,
//            failureType: Error.self,
//            backPressureStrategy:  self.backPressureStrategy,
//            delegate: self.delegate
//        )
//        self.source = result.source
//        self.sequence = result.sequence
//        
//        
//        self.writerDelegate = .init()
//        let newWriter = NIOAsyncWriter.makeWriter(
//            elementType: IRCMessage.self,
//            isWritable: true,
//            delegate: self.writerDelegate
//        )
//        self.writer = newWriter.writer
//        self.sink = newWriter.sink
//        self.iterator = self.sequence?.makeAsyncIterator()
//    }
//    
//    deinit {
//        self.backPressureStrategy = nil
//        self.delegate = nil
//        self.sequence = nil
//        self.writerDelegate = nil
//        self.writer = nil
//        self.sink = nil
//    }
//    
//    public func channelActive(context: ChannelHandlerContext) {
//        self.logger.info("AsyncMessageChannelHandler is Active")
//        context.fireChannelActive()
//    }
//    
//    public func channelInactive(context: ChannelHandlerContext) {
//        self.logger.trace("AsyncMessageChannelHandler is Inactive")
//        context.fireChannelInactive()
//    }
//    
//    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
//        self.logger.trace("AsyncMessageChannelHandler Read")
//        let buffer = self.unwrapInboundIn(data)
//        bufferDeque.append(buffer)
//    }
//    
//    
//    public func channelReadComplete(context: ChannelHandlerContext) {
//        self.logger.trace("AsyncMessageChannelHandler Read Complete")
//        
//        let result = self.source.yield(contentsOf: bufferDeque)
//        switch result {
//        case .produceMore:
//            logger.trace("Produce More")
//            context.read()
//        case .stopProducing:
//            logger.trace("Stop Producing")
//        case .dropped:
//            logger.trace("Dropped Yield Result")
//        }
//        
//        
//        _ = context.eventLoop.executeAsync {
//            func runIterator() async throws {
//                guard var buffer = try await self.iterator?.next() else { throw NeedleTailError.parsingError }
//                
//                guard let lines = buffer.readString(length: buffer.readableBytes) else { return }
//                guard !lines.isEmpty else { return }
//                let messages = lines.components(separatedBy: "\n")
//                    .map { $0.replacingOccurrences(of: "\r", with: "") }
//                    .filter{ $0 != ""}
//                
//                for message in messages {
//                    let parsedMessage = try await AsyncMessageTask.parseMessageTask(task: message, messageParser: self.parser)
//                    try await self.writer.yield(parsedMessage)
//                }
//            }
//            try await runIterator()
//            if self.delegate.produceMoreCallCount != 0 {
//                try await runIterator()
//            }
//        }
//        channelRead(context: context)
//        self.bufferDeque.removeAll()
//    }
//    
//    private func channelRead(context: ChannelHandlerContext) {
//        let promise = context.eventLoop.makePromise(of: Deque<IRCMessage>.self)
//        self.writerDelegate.didYieldHandler = { deq in
//            promise.succeed(deq)
//        }
//        promise.futureResult.whenSuccess { messages in
//            for message in messages {
//                let wioValue = self.wrapInboundOut(message)
//                context.fireChannelRead(wioValue)
//                context.flush()
//            }
//        }
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
//    public func write(
//        context: ChannelHandlerContext,
//        data: NIOAny,
//        promise: EventLoopPromise<Void>?
//    ) {
//
//        let message = self.unwrapOutboundIn(data)
//        let buffer: EventLoopFuture<ByteBuffer> = context.eventLoop.executeAsync {
//            return await self.encode(value: message)
//        }
//        buffer.whenComplete { switch $0 {
//        case .success(let buffer):
//            context.writeAndFlush(NIOAny(buffer), promise: promise)
//        case .failure(let error):
//            self.logger.error("\(error)")
//        }
//        }
//    }
//}
//
//final class NIOBackPressuredStreamSourceDelegate: NIOAsyncSequenceProducerDelegate, @unchecked Sendable {
//    var produceMoreCallCount = 0
//    var produceMoreHandler: (() -> Void)?
//    func produceMore() {
//        self.produceMoreCallCount += 1
//        if let produceMoreHandler = self.produceMoreHandler {
//            return produceMoreHandler()
//        }
//    }
//    
//    var didTerminateCallCount = 0
//    var didTerminateHandler: (() -> Void)?
//    func didTerminate() {
//        self.didTerminateCallCount += 1
//        if let didTerminateHandler = self.didTerminateHandler {
//            return didTerminateHandler()
//        }
//    }
//}
//
//private final class AsyncWriterDelegate: NIOAsyncWriterSinkDelegate, @unchecked Sendable {
//    typealias Element = IRCMessage
//    
//    var didYieldCallCount = 0
//    var didYieldHandler: ((Deque<IRCMessage>) -> Void)?
//    func didYield(contentsOf sequence: Deque<IRCMessage>) {
//        self.didYieldCallCount += 1
//        if let didYieldHandler = self.didYieldHandler {
//            didYieldHandler(sequence)
//        }
//    }
//    
//    var didTerminateCallCount = 0
//    var didTerminateHandler: ((Error?) -> Void)?
//    func didTerminate(error: Error?) {
//        self.didTerminateCallCount += 1
//        if let didTerminateHandler = self.didTerminateHandler {
//            didTerminateHandler(error)
//        }
//    }
//}
