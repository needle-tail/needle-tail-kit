import NIOCore
import Logging
import Foundation
import NeedleTailHelpers
import NIOConcurrencyHelpers
import NIOSSL
import DequeModule

/// Basic syntax:
/// [':' SOURCE]? ' ' COMMAND [' ' ARGS]? [' :' LAST-ARG]?
public final class AsyncMessageChannelHandlerAdapter<InboundIn>: ChannelDuplexHandler, @unchecked Sendable {
    //    public typealias InboundIn   = ByteBuffer
    public typealias InboundOut  = IRCMessage
    public typealias OutboundIn  = IRCMessage
    public typealias OutboundOut = ByteBuffer
    typealias Source = NIOThrowingAsyncSequenceProducer<InboundIn, Error, NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark, AsyncMessageChannelHandlerAdapter<InboundIn>>.Source
    
    
    
    @ParsingActor
    private let parser = MessageParser()
    private let logger: Logger
    private var channel: Channel?
    
    var loop: EventLoop?
    private var dequeSequeneces = Deque<DequeSequence>()
    var context: ChannelHandlerContext?
    
    private var backPressureStrategy: NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark!
    private var delegate: NIOBackPressuredStreamSourceDelegate!
    private var sequence: NIOThrowingAsyncSequenceProducer<
        InboundIn,
        Error,
        NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
        NIOBackPressuredStreamSourceDelegate
    >!
    private var source: NIOThrowingAsyncSequenceProducer<
        InboundIn,
        Error,
        NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
        NIOBackPressuredStreamSourceDelegate
    >.Source!
    
    
    
    
    private let sslServerHandler: NIOSSLServerHandler?
    private var bufferDeque = Deque<InboundIn>()
    private var writer: NIOAsyncWriter<IRCMessage, AsyncWriterDelegate>!
    private var sink: NIOAsyncWriter<IRCMessage, AsyncWriterDelegate>.Sink!
    private var writerDelegate: AsyncWriterDelegate!
    private var iterator: NIOThrowingAsyncSequenceProducer<
        InboundIn,
        Error,
        NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
        NIOBackPressuredStreamSourceDelegate>.AsyncIterator!
    
    public init(
        logger: Logger = Logger(label: "NeedleTailKit"),
        sslServerHandler: NIOSSLServerHandler? = nil
    ) {
        self.logger = logger
        self.sslServerHandler = sslServerHandler
        
        
        self.backPressureStrategy = NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark(lowWatermark: 5, highWatermark: 20)
        self.delegate = .init()
        let result = NIOThrowingAsyncSequenceProducer.makeSequence(
            elementType: InboundIn.self,
            failureType: Error.self,
            backPressureStrategy:  self.backPressureStrategy,
            delegate: self.delegate
        )
        self.source = result.source
        self.sequence = result.sequence
        
        if iterator == nil {
            self.iterator = self.sequence?.makeAsyncIterator()
        }
        
        
        self.writerDelegate = .init()
        let newWriter = NIOAsyncWriter.makeWriter(
            elementType: IRCMessage.self,
            isWritable: true,
            delegate: self.writerDelegate
        )
        self.writer = newWriter.writer
        self.sink = newWriter.sink
        logger.trace("Initalized AsyncMessageChannelHandlerAdapter")
    }
    
    deinit {
        logger.trace("Reclaiming Memory in AsyncMessageChannelHandlerAdapter")
        self.writerDelegate = nil
        self.writer = nil
        self.sink = nil
        self.iterator = nil
    }
    
    public func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        self.channel = context.channel
        self.loop = context.eventLoop
    }
    
    public func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        self.logger.info("AsyncMessageChannelHandlerAdapter is Active")
        context.fireChannelActive()
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        self.logger.trace("AsyncMessageChannelHandlerAdapter is Inactive")
        context.fireChannelInactive()
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.logger.trace("AsyncMessageChannelHandlerAdapter Read")
        bufferDeque.append(self.unwrapInboundIn(data))
    }
    
    var pendingReadState: PendingReadState = .canRead
    enum PendingReadState {
        // Not .stopProducing
        case canRead
        
        // .stopProducing but not read()
        case readBlocked
        
        // .stopProducing and read()
        case pendingRead
    }
    
    public func channelReadComplete(context: ChannelHandlerContext) {
        if self.bufferDeque.isEmpty {
            return
        }
        
        let result = self.source?.yield(contentsOf: self.bufferDeque)
        switch result {
        case .produceMore:
            ()
        case .stopProducing:
            if self.pendingReadState != .pendingRead {
                self.pendingReadState = .readBlocked
            }
        case .dropped:
            fatalError("TODO: can this happen?")
        default:
            fatalError("TODO: can this happen!")
        }
        
        //        let streamResult = context.eventLoop.executeAsync {
        //            guard var buffer = try await self.iterator?.next() as? ByteBuffer else { throw NeedleTailError.parsingError }
        //            guard let lines = buffer.readString(length: buffer.readableBytes) else { return }
        //            guard !lines.isEmpty else { return }
        //            let messages = lines.components(separatedBy: Constants.cLF)
        //                .map { $0.replacingOccurrences(of: Constants.cCR, with: Constants.space) }
        //                .filter { $0 != ""}
        //
        //            for message in messages {
        //                let parsedMessage = try await AsyncMessageTask.parseMessageTask(task: message, messageParser: self.parser)
        //                try await self.writer.yield(parsedMessage)
        //            }
        //        }
        //
        //        streamResult.eventLoop.execute {
        //            self.channelRead(context: context)
        //            self.bufferDeque.removeAll(keepingCapacity: true)
        //        }
        
        let streamResult = context.eventLoop.executeAsync {
            
            while self.bufferDeque.count != 0 && self.bufferDeque.count >= 1 {
                let nextIteration = try await self.iterator.next()
                if self.bufferDeque.count != 0 {
                    let firstMessage = self.bufferDeque.removeFirst()
                    let state = DequeSequenceState.containsElement(nextIteration, firstMessage)
                    self.dequeSequeneces.append(DequeSequence(state: state))
                }
            }
            
            while self.dequeSequeneces.count != 0 && self.dequeSequeneces.count >= 1 {
                switch self.dequeSequeneces.removeFirst().state {
                case .containsElement(let nextIteration, _):
                    do {
                        guard var nextIteration = nextIteration as? ByteBuffer else { return }
                        self.logger.info("Successfully got message from sequence")
                        guard let lines = nextIteration.readString(length: nextIteration.readableBytes) else { return }
                        guard !lines.isEmpty else { return }
                        let messages = lines.components(separatedBy: Constants.cLF)
                            .map { $0.replacingOccurrences(of: Constants.cCR, with: Constants.space) }
                            .filter { $0 != ""}
                        
                        for message in messages {
                            let parsedMessage = try await AsyncMessageTask.parseMessageTask(task: message, messageParser: self.parser)
                            try await self.writer.yield(parsedMessage)
                        }
                    } catch {
                        print(error)
                        //                        self.error = error
                    }
                case .emptyDeque:
                    fatalError("This can't happen")
                case .none:
                    break
                }
            }
        }
        
        streamResult.whenFailure { error in
            self.logger.error("\(error)")
        }
        
        streamResult.eventLoop.execute {
            self.channelRead(context: context)
        }
    }
    
    public func read(context: ChannelHandlerContext) {
        switch self.pendingReadState {
        case .canRead:
            context.read()
        case .readBlocked:
            self.pendingReadState = .pendingRead
        case .pendingRead:
            ()
        }
    }
    
    private func channelRead(context: ChannelHandlerContext) {
        
        func processWrites(_ writes: Deque<IRCMessage>) {
            context.eventLoop.execute {
                var writes = writes
                if writes.count >= 1 {
                    let message = writes.removeFirst()
                    let wioValue = self.wrapInboundOut(message)
                    context.fireChannelRead(wioValue)
                    context.flush()
                    processWrites(writes)
                } else {
                    return
                }
            }
        }
        
        self.writerDelegate.didYieldHandler = { deq in
            processWrites(deq)
        }
        
        context.fireChannelReadComplete()
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
    
    public func write(
        context: ChannelHandlerContext,
        data: NIOAny,
        promise: EventLoopPromise<Void>?
    ) {
        let message = self.unwrapOutboundIn(data)
        let buffer: EventLoopFuture<ByteBuffer> = context.eventLoop.executeAsync {
            return await self.encode(value: message)
        }
        buffer.whenComplete { switch $0 {
        case .success(let buffer):
            context.writeAndFlush(NIOAny(buffer), promise: promise)
        case .failure(let error):
            self.logger.error("\(error)")
        }
        }
    }
    
    private struct DequeSequence {
        var state: DequeSequenceState
    }
    
    private enum DequeSequenceState {
        case containsElement(InboundIn?, InboundIn)
        case emptyDeque
        case none
    }
}


extension AsyncMessageChannelHandlerAdapter: NIOAsyncSequenceProducerDelegate {
    public func didTerminate() {
        self.loop?.execute {
            self.source = nil
            
            // Wedges the read open forever, we'll never read again.
            self.pendingReadState = .pendingRead
        }
    }
    
    public func produceMore() {
        self.loop?.execute {
            switch self.pendingReadState {
            case .readBlocked:
                self.pendingReadState = .canRead
            case .pendingRead:
                self.pendingReadState = .canRead
                self.context?.read()
            case .canRead:
                ()
            }
        }
    }
}

extension AsyncMessageChannelHandlerAdapter {
    enum InboundMessage {
        case channelRead(InboundIn, EventLoopPromise<Void>?)
        case eof
    }
}

extension AsyncMessageChannelHandlerAdapter {
    enum StreamState {
        case bufferingWithoutPendingRead(CircularBuffer<InboundMessage>)
        case bufferingWithPendingRead(CircularBuffer<InboundMessage>, EventLoopPromise<Void>)
        case waitingForBuffer(CircularBuffer<InboundMessage>, CheckedContinuation<InboundMessage, Never>)
    }
}


