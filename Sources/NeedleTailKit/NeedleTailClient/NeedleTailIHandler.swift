//
//  NeedleTailInboundHandler.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIOCore
import Logging
import NeedleTailProtocol
import NeedleTailHelpers
import NIOConcurrencyHelpers
import DequeModule
import BSON
import Foundation

protocol NeedleTailHandlerDelegate: AnyObject {
    func passMessage(_ message: IRCMessage) async throws
}

final class NeedleTailHandler<InboundIn>: ChannelInboundHandler, @unchecked Sendable {
    
    typealias Source = NIOThrowingAsyncSequenceProducer<InboundIn, Error, NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark, NeedleTailHandler<InboundIn>.Delegate>.Source

    var needleTailHandlerDelegate: NeedleTailHandlerDelegate
    
    var logger = Logger(label: "NeedleTailHandler")
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
    var loop: EventLoop?
    var context: ChannelHandlerContext?
    let closeRatchet: CloseRatchet
    var producingState: ProducingState = .keepProducing
    private var messageDeque = Deque<InboundIn>()
    private var iterator: NIOThrowingAsyncSequenceProducer<
        InboundIn,
        Error,
        NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
        NIOBackPressuredStreamSourceDelegate>.AsyncIterator!
    
    private var channel: Channel?
    
    init(
        closeRatchet: CloseRatchet,
        needleTailHandlerDelegate: NeedleTailHandlerDelegate
    ) {
        self.needleTailHandlerDelegate = needleTailHandlerDelegate
        self.logger.logLevel = .info
        self.closeRatchet = closeRatchet
        
        self.backPressureStrategy = NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark(lowWatermark: 2, highWatermark: 10)
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
    }
    
    public func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        self.channel = context.channel
        self.loop = context.eventLoop
    }
    
    public func handlerRemoved(context: ChannelHandlerContext) {
        self._completeStream(context: context)
        self.context = nil
    }
    
    
    func channelActive(context: ChannelHandlerContext) {
        logger.trace("Channel Active")
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        logger.trace("Channel Inactive")
        self._completeStream(context: context)
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
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = self.unwrapInboundIn(data)
        messageDeque.append(buffer)
        self._deliverReads(context: context)
    }
    
    func channelReadComplete(context: ChannelHandlerContext) {
//        self._deliverReads(context: context)
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self._completeStream(with: error, context: context)
        context.fireErrorCaught(error)
    }
    
    func read(context: ChannelHandlerContext) {
        switch self.producingState {
        case .keepProducing:
            context.read()
        case .producingPaused:
            self.producingState = .producingPausedWithOutstandingRead
        case .producingPausedWithOutstandingRead:
            ()
        }
    }
    
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
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
    
    func _deliverReads(context: ChannelHandlerContext) {
        if self.messageDeque.isEmpty { return }
        
        guard let source = self.source else {
            self.messageDeque.removeAll()
            return
        }
        
        let result = source.yield(contentsOf: self.messageDeque)
        switch result {
        case .produceMore, .dropped:
            ()
        case .stopProducing:
            if self.producingState != .producingPausedWithOutstandingRead {
                self.producingState = .producingPaused
            }
        }
        
        self.logger.trace("Successfully got message from sequence in NeedleTailHandler")
        let processedResult = context.eventLoop.executeAsync {
            for message in self.messageDeque {
                let message = message as! ByteBuffer
                let document = Document(buffer: message)
                let decodedMessage = try BSONDecoder().decode(IRCMessage.self, from: document)
                try await self.needleTailHandlerDelegate.passMessage(decodedMessage)
            }
            self.messageDeque.removeAll(keepingCapacity: true)
        }
        
        processedResult.whenFailure { error in
            self.logger.error("\(error)")
        }
    }
}

extension NeedleTailHandler {
    
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

extension NeedleTailHandler {
    
    struct Delegate: @unchecked Sendable, NIOAsyncSequenceProducerDelegate {
        let loop: EventLoop
        let handler: NeedleTailHandler<InboundIn>
        
        init(handler: NeedleTailHandler<InboundIn>) {
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
}

//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2022 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
//#if compiler(>=5.5.2) && canImport(_Concurrency)
//import DequeModule

@usableFromInline
enum ProducingState {
    // Not .stopProducing
    case keepProducing
    
    // .stopProducing but not read()
    case producingPaused
    
    // .stopProducing and read()
    case producingPausedWithOutstandingRead
}

/// A helper type that lets ``NIOAsyncChannelAdapterHandler`` and ``NIOAsyncChannelWriterHandler`` collude
/// to ensure that the ``Channel`` they share is closed appropriately.
///
/// The strategy of this type is that it keeps track of which side has closed, so that the handlers can work out
/// which of them was "last", in order to arrange closure.
@usableFromInline
final class CloseRatchet {
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
    init() {
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
//
///// A `ChannelHandler` that is used to transform the inbound portion of a NIO
///// `Channel` into an `AsyncSequence` that supports backpressure.
//@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
//@usableFromInline
//internal final class NIOAsyncChannelAdapterHandler<InboundIn: Sendable>: ChannelDuplexHandler {
//    @usableFromInline
//    typealias OutboundIn = Any
//
//    @usableFromInline
//    typealias OutboundOut = Any
//
//    @usableFromInline
//    typealias Source = NIOThrowingAsyncSequenceProducer<InboundIn, Error, NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark, NIOAsyncChannelAdapterHandler<InboundIn>.Delegate>.Source
//
//    @usableFromInline var source: Source?
//
//    @usableFromInline var context: ChannelHandlerContext?
//
//    @usableFromInline var buffer: [InboundIn] = []
//
//    @usableFromInline var producingState: ProducingState = .keepProducing
//
//    @usableFromInline let loop: EventLoop
//
//    @usableFromInline let closeRatchet: CloseRatchet
//
//    @inlinable
//    init(loop: EventLoop, closeRatchet: CloseRatchet) {
//        self.loop = loop
//        self.closeRatchet = closeRatchet
//    }
//
//    @inlinable
//    func handlerAdded(context: ChannelHandlerContext) {
//        self.context = context
//    }
//
//    @inlinable
//    func handlerRemoved(context: ChannelHandlerContext) {
//        self._completeStream(context: context)
//        self.context = nil
//    }
//
//    @inlinable
//    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
//        self.buffer.append(self.unwrapInboundIn(data))
//
//        // We forward on reads here to enable better channel composition.
//        context.fireChannelRead(data)
//    }
//
//    @inlinable
//    func channelReadComplete(context: ChannelHandlerContext) {
//        self._deliverReads(context: context)
//        context.fireChannelReadComplete()
//    }
//
//    @inlinable
//    func channelInactive(context: ChannelHandlerContext) {
//        self._completeStream(context: context)
//        context.fireChannelInactive()
//    }
//
//    @inlinable
//    func errorCaught(context: ChannelHandlerContext, error: Error) {
//        self._completeStream(with: error, context: context)
//        context.fireErrorCaught(error)
//    }
//
//    @inlinable
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
//    @inlinable
//    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
//        switch event {
//        case ChannelEvent.inputClosed:
//            self._completeStream(context: context)
//        default:
//            ()
//        }
//
//        context.fireUserInboundEventTriggered(event)
//    }
//
//    @inlinable
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
//    @inlinable
//    func _deliverReads(context: ChannelHandlerContext) {
//        if self.buffer.isEmpty {
//            return
//        }
//
//        guard let source = self.source else {
//            self.buffer.removeAll()
//            return
//        }
//
//        let result = source.yield(contentsOf: self.buffer)
//        switch result {
//        case .produceMore, .dropped:
//            ()
//        case .stopProducing:
//            if self.producingState != .producingPausedWithOutstandingRead {
//                self.producingState = .producingPaused
//            }
//        }
//        self.buffer.removeAll(keepingCapacity: true)
//    }
//}
//
//@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
//extension NIOAsyncChannelAdapterHandler {
//    @inlinable
//    func _didTerminate() {
//        self.loop.preconditionInEventLoop()
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
//    @inlinable
//    func _produceMore() {
//        self.loop.preconditionInEventLoop()
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
//@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
//extension NIOAsyncChannelAdapterHandler {
//    @usableFromInline
//    struct Delegate: @unchecked Sendable, NIOAsyncSequenceProducerDelegate {
//        @usableFromInline
//        let loop: EventLoop
//
//        @usableFromInline
//        let handler: NIOAsyncChannelAdapterHandler<InboundIn>
//
//        @inlinable
//        init(handler: NIOAsyncChannelAdapterHandler<InboundIn>) {
//            self.loop = handler.loop
//            self.handler = handler
//        }
//
//        @inlinable
//        func didTerminate() {
//            self.loop.execute {
//                self.handler._didTerminate()
//            }
//        }
//
//        @inlinable
//        func produceMore() {
//            self.loop.execute {
//                self.handler._produceMore()
//            }
//        }
//    }
//}
//
//@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
//@usableFromInline
//internal final class NIOAsyncChannelWriterHandler<OutboundOut: Sendable>: ChannelDuplexHandler {
//    @usableFromInline typealias InboundIn = Any
//    @usableFromInline typealias InboundOut = Any
//    @usableFromInline typealias OutboundIn = Any
//    @usableFromInline typealias OutboundOut = OutboundOut
//
//    @usableFromInline
//    typealias Writer = NIOAsyncWriter<OutboundOut, NIOAsyncChannelWriterHandler<OutboundOut>.Delegate>
//
//    @usableFromInline
//    typealias Sink = Writer.Sink
//
//    @usableFromInline
//    var sink: Sink?
//
//    @usableFromInline
//    var context: ChannelHandlerContext?
//
//    @usableFromInline
//    let loop: EventLoop
//
//    @usableFromInline
//    let closeRatchet: CloseRatchet
//
//    @usableFromInline
//    let enableOutboundHalfClosure: Bool
//
//    @inlinable
//    init(loop: EventLoop, closeRatchet: CloseRatchet, enableOutboundHalfClosure: Bool) {
//        self.loop = loop
//        self.closeRatchet = closeRatchet
//        self.enableOutboundHalfClosure = enableOutboundHalfClosure
//    }
//
//    @inlinable
//    static func makeHandler(loop: EventLoop, closeRatchet: CloseRatchet, enableOutboundHalfClosure: Bool) -> (NIOAsyncChannelWriterHandler<OutboundOut>, Writer) {
//        let handler = NIOAsyncChannelWriterHandler<OutboundOut>(loop: loop, closeRatchet: closeRatchet, enableOutboundHalfClosure: enableOutboundHalfClosure)
//        let writerComponents = Writer.makeWriter(elementType: OutboundOut.self, isWritable: true, delegate: Delegate(handler: handler))
//        handler.sink = writerComponents.sink
//        return (handler, writerComponents.writer)
//    }
//
//    @inlinable
//    func _didYield(sequence: Deque<OutboundOut>) {
//        // This is always called from an async context, so we must loop-hop.
//        // Because we always loop-hop, we're always at the top of a stack frame. As this
//        // is the only source of writes for us, and as this channel handler doesn't implement
//        // func write(), we cannot possibly re-entrantly write. That means we can skip many of the
//        // awkward re-entrancy protections NIO usually requires, and can safely just do an iterative
//        // write.
//        self.loop.preconditionInEventLoop()
//        guard let context = self.context else {
//            // Already removed from the channel by now, we can stop.
//            return
//        }
//
//        self._doOutboundWrites(context: context, writes: sequence)
//    }
//
//    @inlinable
//    func _didTerminate(error: Error?) {
//        self.loop.preconditionInEventLoop()
//
//        switch self.closeRatchet.closeWrite() {
//        case .nothing:
//            if self.enableOutboundHalfClosure {
//                self.context?.close(mode: .output, promise: nil)
//            }
//        case .close:
//            self.context?.close(promise: nil)
//        }
//
//        self.sink = nil
//    }
//
//    @inlinable
//    func _doOutboundWrites(context: ChannelHandlerContext, writes: Deque<OutboundOut>) {
//        for write in writes {
//            context.write(self.wrapOutboundOut(write), promise: nil)
//        }
//
//        context.flush()
//    }
//
//    @inlinable
//    func handlerAdded(context: ChannelHandlerContext) {
//        self.context = context
//    }
//
//    @inlinable
//    func handlerRemoved(context: ChannelHandlerContext) {
//        self.context = nil
//        self.sink = nil
//    }
//
//    @inlinable
//    func errorCaught(context: ChannelHandlerContext, error: Error) {
//        self.sink?.finish(error: error)
//        context.fireErrorCaught(error)
//    }
//
//    @inlinable
//    func channelInactive(context: ChannelHandlerContext) {
//        self.sink?.finish()
//        context.fireChannelInactive()
//    }
//
//    @inlinable
//    func channelWritabilityChanged(context: ChannelHandlerContext) {
//        self.sink?.setWritability(to: context.channel.isWritable)
//        context.fireChannelWritabilityChanged()
//    }
//}
//
//@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
//extension NIOAsyncChannelWriterHandler {
//    @usableFromInline
//    struct Delegate: @unchecked Sendable, NIOAsyncWriterSinkDelegate {
//        @usableFromInline
//        typealias Element = OutboundOut
//
//        @usableFromInline
//        let loop: EventLoop
//
//        @usableFromInline
//        let handler: NIOAsyncChannelWriterHandler<OutboundOut>
//
//        @inlinable
//        init(handler: NIOAsyncChannelWriterHandler<OutboundOut>) {
//            self.loop = handler.loop
//            self.handler = handler
//        }
//
//        @inlinable
//        func didYield(contentsOf sequence: Deque<OutboundOut>) {
//            self.loop.execute {
//                self.handler._didYield(sequence: sequence)
//            }
//        }
//
//        @inlinable
//        func didTerminate(error: Error?) {
//            // This always called from an async context, so we must loop-hop.
//            self.loop.execute {
//                self.handler._didTerminate(error: error)
//            }
//        }
//    }
//}
//
//@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
//public struct NIOInboundChannelStream<InboundIn: Sendable>: Sendable {
//    @usableFromInline
//    typealias Producer = NIOThrowingAsyncSequenceProducer<InboundIn, Error, NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark, NIOAsyncChannelAdapterHandler<InboundIn>.Delegate>
//
//    @usableFromInline let _producer: Producer
//
//    @inlinable
//    init(_ channel: Channel, backpressureStrategy: NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark?, closeRatchet: CloseRatchet) throws {
//        channel.eventLoop.preconditionInEventLoop()
//        let handler = NIOAsyncChannelAdapterHandler<InboundIn>(loop: channel.eventLoop, closeRatchet: closeRatchet)
//        let strategy: NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark
//
//        if let userProvided = backpressureStrategy {
//            strategy = userProvided
//        } else {
//            // Default strategy. These numbers are fairly arbitrary, but they line up with the default value of
//            // maxMessagesPerRead.
//            strategy = .init(lowWatermark: 2, highWatermark: 10)
//        }
//
//        let sequence = Producer.makeSequence(backPressureStrategy: strategy, delegate: NIOAsyncChannelAdapterHandler<InboundIn>.Delegate(handler: handler))
//        handler.source = sequence.source
//        try channel.pipeline.syncOperations.addHandler(handler)
//        self._producer = sequence.sequence
//    }
//}
//
//@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
//extension NIOInboundChannelStream: AsyncSequence {
//    public typealias Element = InboundIn
//
//    public struct AsyncIterator: AsyncIteratorProtocol {
//        @usableFromInline var _iterator: Producer.AsyncIterator
//
//        @inlinable
//        init(_ iterator: Producer.AsyncIterator) {
//            self._iterator = iterator
//        }
//
//        @inlinable public func next() async throws -> Element? {
//            return try await self._iterator.next()
//        }
//    }
//
//    @inlinable
//    public func makeAsyncIterator() -> AsyncIterator {
//        return AsyncIterator(self._producer.makeAsyncIterator())
//    }
//}
//
//@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
//@available(*, unavailable)
//extension NIOAsyncChannelAdapterHandler: Sendable {}
//
//@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
//@available(*, unavailable)
//extension NIOAsyncChannelWriterHandler: Sendable {}
//
///// The ``NIOInboundChannelStream/AsyncIterator`` MUST NOT be shared across `Task`s. With marking this as
///// unavailable we are explicitly declaring this.
//@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
//@available(*, unavailable)
//extension NIOInboundChannelStream.AsyncIterator: Sendable {}
//#endif
//
//
////===----------------------------------------------------------------------===//
////
//// This source file is part of the SwiftNIO open source project
////
//// Copyright (c) 2022 Apple Inc. and the SwiftNIO project authors
//// Licensed under Apache License v2.0
////
//// See LICENSE.txt for license information
//// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
////
//// SPDX-License-Identifier: Apache-2.0
////
////===----------------------------------------------------------------------===//
//
//#if compiler(>=5.5.2) && canImport(_Concurrency)
//
///// Wraps a NIO ``Channel`` object into a form suitable for use in Swift Concurrency.
/////
///// ``NIOAsyncChannel`` abstracts the notion of a NIO ``Channel`` into something that
///// can safely be used in a structured concurrency context. In particular, this exposes
///// the following functionality:
/////
///// - reads are presented as an `AsyncSequence`
///// - writes can be written to with async functions, providing backpressure
///// - channels can be closed seamlessly
/////
///// This type does not replace the full complexity of NIO's ``Channel``. In particular, it
///// does not expose the following functionality:
/////
///// - user events
///// - traditional NIO backpressure such as writability signals and the ``Channel/read()`` call
/////
///// Users are encouraged to separate their ``ChannelHandler``s into those that implement
///// protocol-specific logic (such as parsers and encoders) and those that implement business
///// logic. Protocol-specific logic should be implemented as a ``ChannelHandler``, while business
///// logic should use ``NIOAsyncChannel`` to consume and produce data to the network.
//@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
//public final class NIOAsyncChannel<InboundIn: Sendable, OutboundOut: Sendable>: Sendable {
//    /// The underlying channel being wrapped by this ``NIOAsyncChannel``.
//    public let channel: Channel
//
//    public let inboundStream: NIOInboundChannelStream<InboundIn>
//
//    @usableFromInline
//    let outboundWriter: NIOAsyncChannelWriterHandler<OutboundOut>.Writer
//
//    @inlinable
//    public init(
//        wrapping channel: Channel,
//        backpressureStrategy: NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark? = nil,
//        enableOutboundHalfClosure: Bool = true,
//        inboundIn: InboundIn.Type = InboundIn.self,
//        outboundOut: OutboundOut.Type = OutboundOut.self
//    ) async throws {
//        (self.inboundStream, self.outboundWriter) = try await channel.eventLoop.submit {
//            try channel.syncAddAsyncHandlers(backpressureStrategy: backpressureStrategy, enableOutboundHalfClosure: enableOutboundHalfClosure)
//        }.get()
//
//        self.channel = channel
//    }
//
//    @inlinable
//    public init(
//        synchronouslyWrapping channel: Channel,
//        backpressureStrategy: NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark? = nil,
//        enableOutboundHalfClosure: Bool = true,
//        inboundIn: InboundIn.Type = InboundIn.self,
//        outboundOut: OutboundOut.Type = OutboundOut.self
//    ) throws {
//        channel.eventLoop.preconditionInEventLoop()
//        (self.inboundStream, self.outboundWriter) = try channel.syncAddAsyncHandlers(backpressureStrategy: backpressureStrategy, enableOutboundHalfClosure: enableOutboundHalfClosure)
//        self.channel = channel
//    }
//
//    @inlinable
//    public func writeAndFlush(_ data: OutboundOut) async throws {
//        try await self.outboundWriter.yield(data)
//    }
//
//    @inlinable
//    public func writeAndFlush<Writes: Sequence>(contentsOf data: Writes) async throws where Writes.Element == OutboundOut {
//        try await self.outboundWriter.yield(contentsOf: data)
//    }
//}
//
//extension Channel {
//    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
//    @inlinable
//    func syncAddAsyncHandlers<InboundIn: Sendable, OutboundOut: Sendable>(
//        backpressureStrategy: NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark?,
//        enableOutboundHalfClosure: Bool
//    ) throws -> (NIOInboundChannelStream<InboundIn>, NIOAsyncChannelWriterHandler<OutboundOut>.Writer) {
//        self.eventLoop.assertInEventLoop()
//
//        let closeRatchet = CloseRatchet()
//        let inboundStream = try NIOInboundChannelStream<InboundIn>(self, backpressureStrategy: backpressureStrategy, closeRatchet: closeRatchet)
//        let (handler, writer) = NIOAsyncChannelWriterHandler<OutboundOut>.makeHandler(loop: self.eventLoop, closeRatchet: closeRatchet, enableOutboundHalfClosure: enableOutboundHalfClosure)
//        try self.pipeline.syncOperations.addHandler(handler)
//        return (inboundStream, writer)
//    }
//}
//#endif
