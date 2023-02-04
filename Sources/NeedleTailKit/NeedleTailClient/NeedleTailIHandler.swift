////
////  NeedleTailInboundHandler.swift
////  
////
////  Created by Cole M on 3/4/22.
////
//
//import NIOCore
//import Logging
//import NeedleTailProtocol
//import NeedleTailHelpers
//import NIOConcurrencyHelpers
//import DequeModule
//import BSON
//import Foundation
//
//protocol NeedleTailHandlerDelegate: AnyObject {
//    func passMessage(_ message: IRCMessage) async throws
//}
//
//final class NeedleTailHandler<InboundIn>: ChannelInboundHandler, @unchecked Sendable {
//    
//    typealias Source = NIOThrowingAsyncSequenceProducer<InboundIn, Error, NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark, NeedleTailHandler<InboundIn>.Delegate>.Source
//
//    var needleTailHandlerDelegate: NeedleTailHandlerDelegate
//    
//    var logger = Logger(label: "NeedleTailHandler")
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
//    var loop: EventLoop?
//    var context: ChannelHandlerContext?
//    let closeRatchet: CloseRatchet
//    var producingState: ProducingState = .keepProducing
//    private var bufferDeque = Deque<ByteBuffer>()
//    private var iterator: NIOThrowingAsyncSequenceProducer<
//        ByteBuffer,
//        Error,
//        NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
//        NIOBackPressuredStreamSourceDelegate>.AsyncIterator!
//    
//    private var channel: Channel?
//    
//    init(
//        closeRatchet: CloseRatchet,
//        needleTailHandlerDelegate: NeedleTailHandlerDelegate
//    ) {
//        self.needleTailHandlerDelegate = needleTailHandlerDelegate
//        self.logger.logLevel = .info
//        self.closeRatchet = closeRatchet
//        
//        self.backPressureStrategy = NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark(lowWatermark: 2, highWatermark: 10)
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
//        if iterator == nil {
//            self.iterator = self.sequence?.makeAsyncIterator()
//        }
//    }
//    
//    public func handlerAdded(context: ChannelHandlerContext) {
//        self.context = context
//        self.channel = context.channel
//        self.loop = context.eventLoop
//    }
//    
//    public func handlerRemoved(context: ChannelHandlerContext) {
//        self._completeStream(context: context)
//        self.context = nil
//    }
//    
//    
//    func channelActive(context: ChannelHandlerContext) {
//        logger.trace("Channel Active")
//    }
//    
//    func channelInactive(context: ChannelHandlerContext) {
//        logger.trace("Channel Inactive")
//        self._completeStream(context: context)
//    }
//    
//    var pendingReadState: PendingReadState = .canRead
//    enum PendingReadState {
//        // Not .stopProducing
//        case canRead
//        
//        // .stopProducing but not read()
//        case readBlocked
//        
//        // .stopProducing and read()
//        case pendingRead
//    }
//    
//    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
//        let buffer = self.unwrapInboundIn(data) as! ByteBuffer
////        if !bufferDeque.contains(where: { $0.readableBytes == buffer.readableBytes }) {
//            bufferDeque.append(buffer)
////        }
//    }
//    
//    func channelReadComplete(context: ChannelHandlerContext) {
//        self._deliverReads(context: context)
//    }
//    
//    func errorCaught(context: ChannelHandlerContext, error: Error) {
//        self._completeStream(with: error, context: context)
//    }
//    
//    func read(context: ChannelHandlerContext) {
//        switch self.producingState {
//        case .keepProducing:
//            context.read()
//        case .producingPaused:
//            self.producingState = .producingPausedWithOutstandingRead
//        case .producingPausedWithOutstandingRead:
//            ()
//        }
//    }
//    
//    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
//        switch event {
//        case ChannelEvent.inputClosed:
//            self._completeStream(context: context)
//        default:
//            ()
//        }
//        context.fireUserInboundEventTriggered(event)
//    }
//    
//    func _completeStream(with error: Error? = nil, context: ChannelHandlerContext) {
//        guard let source = self.source else {
//            return
//        }
//        
//        self._deliverReads(context: context)
//        
//        if let error = error {
//            source.finish(error)
//        } else {
//            source.finish()
//        }
//        
//        // We can nil the source here, as we're no longer going to use it.
//        self.source = nil
//    }
//    
//    func _deliverReads(context: ChannelHandlerContext) {
//        if self.bufferDeque.isEmpty { return }
//        
//        guard let source = self.source else {
//            self.bufferDeque.removeAll()
//            return
//        }
//        
//        let result = source.yield(contentsOf: self.bufferDeque)
//        switch result {
//        case .produceMore, .dropped:
//            ()
//        case .stopProducing:
//            if self.producingState != .producingPausedWithOutstandingRead {
//                self.producingState = .producingPaused
//            }
//        }
//        
//        self.logger.trace("Successfully got message from sequence in NeedleTailHandler")
////        let processedResult = context.eventLoop.executeAsync {
//        Task {
//                guard let buffer = try await self.iterator.next() else { return }
//                let document = Document(buffer: buffer)
//                let decodedMessage = try BSONDecoder().decode(IRCMessage.self, from: document)
//                try await self.needleTailHandlerDelegate.passMessage(decodedMessage)
//        }
//        
////        processedResult.whenSuccess { _ in
//            self.bufferDeque.removeAll(keepingCapacity: true)
////        }
////        processedResult.whenFailure { error in
////            self.logger.error("\(error)")
////            self.bufferDeque.removeAll(keepingCapacity: true)
////        }
//    }
//}
//
//extension NeedleTailHandler {
//    
//    func _didTerminate() {
//        self.loop?.preconditionInEventLoop()
//        self.source = nil
//        
//        // Wedges the read open forever, we'll never read again.
//        self.producingState = .producingPausedWithOutstandingRead
//        
//        switch self.closeRatchet.closeRead() {
//        case .nothing:
//            ()
//        case .close:
//            self.context?.close(promise: nil)
//        }
//    }
//    
//    
//    func _produceMore() {
//        self.loop?.preconditionInEventLoop()
//        
//        switch self.producingState {
//        case .producingPaused:
//            self.producingState = .keepProducing
//        case .producingPausedWithOutstandingRead:
//            self.producingState = .keepProducing
//            self.context?.read()
//        case .keepProducing:
//            ()
//        }
//    }
//}
//
//extension NeedleTailHandler {
//    
//    struct Delegate: @unchecked Sendable, NIOAsyncSequenceProducerDelegate {
//        let loop: EventLoop
//        let handler: NeedleTailHandler<InboundIn>
//        
//        init(handler: NeedleTailHandler<InboundIn>) {
//            self.loop = handler.loop!
//            self.handler = handler
//        }
//        
//        func didTerminate() {
//            self.loop.execute {
//                self.handler._didTerminate()
//            }
//        }
//        
//        func produceMore() {
//            self.loop.execute {
//                self.handler._produceMore()
//            }
//        }
//    }
//}
//
//
//@usableFromInline
//enum ProducingState {
//    // Not .stopProducing
//    case keepProducing
//    
//    // .stopProducing but not read()
//    case producingPaused
//    
//    // .stopProducing and read()
//    case producingPausedWithOutstandingRead
//}
//
///// A helper type that lets ``NIOAsyncChannelAdapterHandler`` and ``NIOAsyncChannelWriterHandler`` collude
///// to ensure that the ``Channel`` they share is closed appropriately.
/////
///// The strategy of this type is that it keeps track of which side has closed, so that the handlers can work out
///// which of them was "last", in order to arrange closure.
//@usableFromInline
//final class CloseRatchet {
//    @usableFromInline
//    enum State {
//        case notClosed
//        case readClosed
//        case writeClosed
//        case bothClosed
//        
//        @inlinable
//        mutating func closeRead() -> Action {
//            switch self {
//            case .notClosed:
//                self = .readClosed
//                return .nothing
//            case .writeClosed:
//                self = .bothClosed
//                return .close
//            case .readClosed, .bothClosed:
//                preconditionFailure("Duplicate read closure")
//            }
//        }
//        
//        @inlinable
//        mutating func closeWrite() -> Action {
//            switch self {
//            case .notClosed:
//                self = .writeClosed
//                return .nothing
//            case .readClosed:
//                self = .bothClosed
//                return .close
//            case .writeClosed, .bothClosed:
//                preconditionFailure("Duplicate write closure")
//            }
//        }
//    }
//    
//    @usableFromInline
//    enum Action {
//        case nothing
//        case close
//    }
//    
//    @usableFromInline
//    var _state: State
//    
//    @inlinable
//    init() {
//        self._state = .notClosed
//    }
//    
//    @inlinable
//    func closeRead() -> Action {
//        return self._state.closeRead()
//    }
//    
//    @inlinable
//    func closeWrite() -> Action {
//        return self._state.closeWrite()
//    }
//}
