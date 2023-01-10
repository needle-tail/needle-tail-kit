import NIOCore
import Logging
import Foundation
import NeedleTailHelpers
import NIOConcurrencyHelpers
import NIOSSL
import DequeModule
import BSON
import CypherMessaging

/// Basic syntax:
/// [':' SOURCE]? ' ' COMMAND [' ' ARGS]? [' :' LAST-ARG]?
public final class AsyncMessageChannelHandlerAdapter<InboundIn, OutboundOut>: ChannelDuplexHandler, @unchecked Sendable {
    public typealias InboundOut = ByteBuffer
    public typealias OutboundIn = IRCMessage
    typealias Source = NIOThrowingAsyncSequenceProducer<InboundIn, Error, NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark, AsyncMessageChannelHandlerAdapter<InboundIn, OutboundOut>.Delegate>.Source
    typealias Writer = NIOAsyncWriter<OutboundOut, AsyncMessageChannelHandlerAdapter<InboundIn, OutboundOut>.WriterDelegate>
    typealias Sink = Writer.Sink
    
    

    private let logger: Logger
    private var context: ChannelHandlerContext?
    private var channel: Channel?
    private var loop: EventLoop?
    private var sink: Sink?
    private var writer: Writer?
    private let closeRatchet: CloseRatchet
    private var producingState: ProducingState = .keepProducing
    @ParsingActor
    private let parser = MessageParser()
    
    

    
    private var backPressureStrategy: NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark!
    private var delegate: NIOBackPressuredStreamSourceDelegate!
    private var sequence: NIOThrowingAsyncSequenceProducer<
        ByteBuffer,
        Error,
        NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
        NIOBackPressuredStreamSourceDelegate
    >!
    private var source: NIOThrowingAsyncSequenceProducer<
        ByteBuffer,
        Error,
        NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
        NIOBackPressuredStreamSourceDelegate
    >.Source!

    private let sslServerHandler: NIOSSLServerHandler?
    private var bufferDeque = Deque<ByteBuffer>()
    private var iterator: NIOThrowingAsyncSequenceProducer<
        ByteBuffer,
        Error,
        NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
        NIOBackPressuredStreamSourceDelegate>.AsyncIterator!
    
    public init(
        logger: Logger = Logger(label: "NeedleTailKit"),
        sslServerHandler: NIOSSLServerHandler? = nil,
        closeRatchet: CloseRatchet
    ) {
        self.logger = logger
        self.sslServerHandler = sslServerHandler
        self.closeRatchet = closeRatchet
        
        self.backPressureStrategy = NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark(lowWatermark: 2, highWatermark: 10)
        self.delegate = .init()
        let result = NIOThrowingAsyncSequenceProducer.makeSequence(
            elementType: ByteBuffer.self,
            failureType: Error.self,
            backPressureStrategy:  self.backPressureStrategy,
            delegate: self.delegate
        )
        self.source = result.source
        self.sequence = result.sequence
        
        if iterator == nil {
            self.iterator = self.sequence?.makeAsyncIterator()
        }
        logger.trace("Initalized AsyncMessageChannelHandlerAdapter")
    }
    
    deinit {
        logger.trace("Reclaiming Memory in AsyncMessageChannelHandlerAdapter")
        self.writer = nil
        self.sink = nil
        self.iterator = nil
    }
    
    public func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        self.channel = context.channel
        self.loop = context.eventLoop
        let writerComponents = Writer.makeWriter(elementType: OutboundOut.self, isWritable: true, delegate: WriterDelegate(handler: self))
        writer = writerComponents.writer
        sink = writerComponents.sink
    }
    
    public func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
        self.sink = nil
    }

    public func errorCaught(context: ChannelHandlerContext, error: Swift.Error) {
        let error = MessageParserError.transportError(error)
        if sslServerHandler != nil {
            logger.error("Parsing Error is: \(error)")
            let promise = context.eventLoop.makePromise(of: Void.self)
            self.sslServerHandler?.stopTLS(promise: promise)
        }
        self._completeStream(with: error, context: context)
        self.sink?.finish(error: error)
        context.fireErrorCaught(error)
    }

    public func channelActive(context: ChannelHandlerContext) {
        logger.trace("Channel Active")
        context.fireChannelActive()
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        logger.trace("Channel Inactive")
        self._completeStream(context: context)
        self.sink?.finish()
        context.fireChannelInactive()
    }
    
    public func channelWritabilityChanged(context: ChannelHandlerContext) {
        self.sink?.setWritability(to: context.channel.isWritable)
        context.fireChannelWritabilityChanged()
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
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = self.unwrapInboundIn(data) as! ByteBuffer
//        if !bufferDeque.contains(where: { $0.readableBytes == message.readableBytes }) {
            bufferDeque.append(message)
//        }
    }
    public func channelReadComplete(context: ChannelHandlerContext) {
        self._deliverReads(context: context)
    }
    
    public func read(context: ChannelHandlerContext) {
        switch self.producingState {
        case .keepProducing:
            context.read()
        case .producingPaused:
            self.producingState = .producingPausedWithOutstandingRead
        case .producingPausedWithOutstandingRead:
            ()
        }
    }
    
    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case ChannelEvent.inputClosed:
            self._completeStream(context: context)
        default:
            ()
        }
        context.fireUserInboundEventTriggered(event)
    }
    
    func _completeStream(with error: Error? = nil, context: ChannelHandlerContext) {
        guard let source = self.source else {
            return
        }
        
        self._deliverReads(context: context)
        
        if let error = error {
            source.finish(error)
        } else {
            source.finish()
        }
        
        // We can nil the source here, as we're no longer going to use it.
        self.source = nil
    }
    var stringDeque = Deque<String>()
    func _deliverReads(context: ChannelHandlerContext) {
        if self.bufferDeque.isEmpty { return }
        
        guard let source = self.source else {
            self.bufferDeque.removeAll()
            return
        }
        
        let result = source.yield(contentsOf: self.bufferDeque)
        switch result {
        case .produceMore, .dropped:
            ()
        case .stopProducing:
            if self.producingState != .producingPausedWithOutstandingRead {
                self.producingState = .producingPaused
            }
        }
        
        for buffer in self.bufferDeque {
            var buffer = buffer
            self.logger.trace("Successfully got message from sequence in AsyncMessageChannelHandlerAdapter")
            guard let message = buffer.readString(length: buffer.readableBytes) else { return }
            guard !message.isEmpty else { return }
            let messages = message.components(separatedBy: Constants.cLF)
                .map { $0.replacingOccurrences(of: Constants.cCR, with: Constants.space) }
                .filter { !$0.isEmpty }
            stringDeque.append(contentsOf: messages)
        }
        
        let parsedYielded = context.eventLoop.executeAsync {
            for message in self.stringDeque {
                     let parsedMessage = try await AsyncMessageTask.parseMessageTask(task: message, messageParser: self.parser)
                    let data = try BSONEncoder().encode(parsedMessage).makeData()
                    let buffer = ByteBuffer(data: data)
                    try await self.writer?.yield(buffer as! OutboundOut)
                }
        }
        parsedYielded.whenSuccess { _ in
            context.fireChannelReadComplete()
            self.stringDeque.removeAll(keepingCapacity: true)
            self.bufferDeque.removeAll(keepingCapacity: true)
        }
        parsedYielded.whenFailure { error in
            self.logger.error("\(error)")
            self.stringDeque.removeAll(keepingCapacity: true)
            self.bufferDeque.removeAll(keepingCapacity: true)
        }
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
    
    private func forwardWrites(context: ChannelHandlerContext, writes: Deque<OutboundOut>) {
        for write in writes {
            let wioValue = self.wrapInboundOut(write as! ByteBuffer)
            context.fireChannelRead(wioValue)
            context.flush()
        }
    }
}

extension AsyncMessageChannelHandlerAdapter {
    
    func _didTerminate() {
        self.loop?.preconditionInEventLoop()
        self.source = nil
        
        // Wedges the read open forever, we'll never read again.
        self.producingState = .producingPausedWithOutstandingRead
        
        switch self.closeRatchet.closeRead() {
        case .nothing:
            ()
        case .close:
            self.context?.close(promise: nil)
        }
    }
    
    
    func _produceMore() {
        self.loop?.preconditionInEventLoop()
        
        switch self.producingState {
        case .producingPaused:
            self.producingState = .keepProducing
        case .producingPausedWithOutstandingRead:
            self.producingState = .keepProducing
            self.context?.read()
        case .keepProducing:
            ()
        }
    }
}

extension AsyncMessageChannelHandlerAdapter {
    
    struct Delegate: @unchecked Sendable, NIOAsyncSequenceProducerDelegate {
        let loop: EventLoop
        let handler: AsyncMessageChannelHandlerAdapter<InboundIn, OutboundOut>
        
        init(handler: AsyncMessageChannelHandlerAdapter<InboundIn, OutboundOut>) {
            self.loop = handler.loop!
            self.handler = handler
        }
        
        func didTerminate() {
            self.loop.execute {
                self.handler._didTerminate()
            }
        }
        
        func produceMore() {
            self.loop.execute {
                self.handler._produceMore()
            }
        }
    }
    
    
        struct WriterDelegate: @unchecked Sendable, NIOAsyncWriterSinkDelegate {
            typealias Element = OutboundOut
    
            let loop: EventLoop
            let handler: AsyncMessageChannelHandlerAdapter<InboundIn, OutboundOut>
    
            init(handler: AsyncMessageChannelHandlerAdapter<InboundIn, OutboundOut>) {
                self.loop = handler.loop!
                self.handler = handler
            }
    
            func didYield(contentsOf sequence: Deque<OutboundOut>) {
                self.loop.execute {
                    self.handler._didYield(sequence: sequence)
                }
            }
    
            func didTerminate(error: Error?) {
                // This always called from an async context, so we must loop-hop.
                self.loop.execute {
                    self.handler._didTerminate(error: error)
                }
            }
        }

}

//WriterDelegate
extension AsyncMessageChannelHandlerAdapter {

    func _didYield(sequence: Deque<OutboundOut>) {
        // This is always called from an async context, so we must loop-hop.
        // Because we always loop-hop, we're always at the top of a stack frame. As this
        // is the only source of writes for us, and as this channel handler doesn't implement
        // func write(), we cannot possibly re-entrantly write. That means we can skip many of the
        // awkward re-entrancy protections NIO usually requires, and can safely just do an iterative
        // write.
        self.loop?.preconditionInEventLoop()
        guard let context = self.context else {
            // Already removed from the channel by now, we can stop.
            return
        }

        self._doOutboundWrites(context: context, writes: sequence)
    }

    func _didTerminate(error: Error?) {
        self.loop?.preconditionInEventLoop()

        switch self.closeRatchet.closeWrite() {
        case .nothing:
            break
//            if self.enableOutboundHalfClosure {
//                self.context?.close(mode: .output, promise: nil)
//            }
        case .close:
            self.context?.close(promise: nil)
        }

        self.sink = nil
    }

    func _doOutboundWrites(context: ChannelHandlerContext, writes: Deque<OutboundOut>) {
        forwardWrites(context: context, writes: writes)
    }
}



public final class CloseRatchet {
    
    @usableFromInline
    enum State {
        case notClosed
        case readClosed
        case writeClosed
        case bothClosed
        
        @inlinable
        mutating func closeRead() -> Action {
            switch self {
            case .notClosed:
                self = .readClosed
                return .nothing
            case .writeClosed:
                self = .bothClosed
                return .close
            case .readClosed, .bothClosed:
                preconditionFailure("Duplicate read closure")
            }
        }
        
        @inlinable
        mutating func closeWrite() -> Action {
            switch self {
            case .notClosed:
                self = .writeClosed
                return .nothing
            case .readClosed:
                self = .bothClosed
                return .close
            case .writeClosed, .bothClosed:
                preconditionFailure("Duplicate write closure")
            }
        }
    }
    
    @usableFromInline
    enum Action {
        case nothing
        case close
    }
    
    @usableFromInline
    var _state: State
    
    @inlinable
    public init() {
        self._state = .notClosed
    }
    
    @inlinable
    func closeRead() -> Action {
        return self._state.closeRead()
    }
    
    @inlinable
    func closeWrite() -> Action {
        return self._state.closeWrite()
    }
}

@usableFromInline
enum ProducingState {
    // Not .stopProducing
    case keepProducing
    
    // .stopProducing but not read()
    case producingPaused
    
    // .stopProducing and read()
    case producingPausedWithOutstandingRead
}
