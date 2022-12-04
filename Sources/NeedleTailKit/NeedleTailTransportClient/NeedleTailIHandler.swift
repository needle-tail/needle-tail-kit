//
//  NeedleTailInboundHandler.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIO
import Logging
import NeedleTailProtocol
import NeedleTailHelpers
import NIOConcurrencyHelpers
import DequeModule


final class NeedleTailHandler<InboundIn>: ChannelInboundHandler, @unchecked Sendable {
    
    typealias Source = NIOThrowingAsyncSequenceProducer<InboundIn, Error, NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark, NeedleTailHandler<InboundIn>>.Source
    
    let client: NeedleTailClient
    let transport: NeedleTailTransport
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
    
    
    private var messageDeque = Deque<InboundIn>()
    private var dequeSequeneces = Deque<DequeSequence>()
    private var iterator: NIOThrowingAsyncSequenceProducer<
        InboundIn,
        Error,
        NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
        NIOBackPressuredStreamSourceDelegate>.AsyncIterator!
    
    private var channel: Channel?
    
    init(client: NeedleTailClient, transport: NeedleTailTransport) {
        self.client = client
        self.transport = transport
        self.logger.logLevel = .trace
        
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
    }
    
    public func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        self.channel = context.channel
        self.loop = context.eventLoop
    }
    
    public func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
    }
    
    
    func channelActive(context: ChannelHandlerContext) {
        logger.trace("Channel Active")
//        context.fireChannelActive()
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        logger.trace("Channel Inactive")
//        context.fireChannelInactive()
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
        print("CHANNEL_READ____")
        messageDeque.append(self.unwrapInboundIn(data))
    }
    
    func channelReadComplete(context: ChannelHandlerContext) {
        if self.messageDeque.isEmpty {
            return
        }
        
        let result = self.source?.yield(contentsOf: self.messageDeque)
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
        
        
        let streamResult = context.eventLoop.executeAsync {
            
            while self.messageDeque.count != 0 && self.messageDeque.count >= 1 {
                let nextIteration = try await self.iterator.next()
                if self.messageDeque.count != 0 {
                    let firstMessage = self.messageDeque.removeFirst()
                    let state = DequeSequenceState.containsElement(nextIteration, firstMessage)
                    self.dequeSequeneces.append(DequeSequence(state: state))
                }
            }
            
            while self.dequeSequeneces.count != 0 && self.dequeSequeneces.count >= 1 {
                switch self.dequeSequeneces.removeFirst().state {
                case .containsElement(let nextIteration, _):
                        self.logger.info("Successfully got message from sequence")
                        do {
                            guard let nextIteration = nextIteration as? IRCMessage else { return }
                            try await self.transport.processReceivedMessages(nextIteration)
                        } catch let error as NeedleTailError {
                            self.logger.error("\(error.rawValue)")
                        } catch {
                            self.logger.error("\(error)")
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
        
//        streamResult.eventLoop.execute {
//            self.channelRead(context: context)
//        }
        
        
        
        
        
//        let message = self.unwrapInboundIn(data)
//        _ = context.eventLoop.executeAsync {
//            do {
//                try await self.transport.processReceivedMessages(message)
//            } catch let error as NeedleTailError {
//                self.logger.error("\(error.rawValue)")
//            } catch {
//                self.logger.error("\(error)")
//            }
//        }
    }
    
    private struct DequeSequence: Sendable {
        var state: DequeSequenceState
    }
    
    private enum DequeSequenceState: @unchecked Sendable {
        case containsElement(InboundIn?, InboundIn)
        case emptyDeque
        case none
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
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

extension NeedleTailHandler: NIOAsyncSequenceProducerDelegate {
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


extension NeedleTailHandler {
    enum InboundMessage {
        case channelRead(InboundIn, EventLoopPromise<Void>?)
        case eof
    }
}

extension NeedleTailHandler {
    enum StreamState {
        case bufferingWithoutPendingRead(CircularBuffer<InboundMessage>)
        case bufferingWithPendingRead(CircularBuffer<InboundMessage>, EventLoopPromise<Void>)
        case waitingForBuffer(CircularBuffer<InboundMessage>, CheckedContinuation<InboundMessage, Never>)
    }
}
