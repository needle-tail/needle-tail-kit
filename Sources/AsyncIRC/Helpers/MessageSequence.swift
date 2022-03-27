//
//  MessageSequence.swift
//  
//
//  Created by Cole M on 3/26/22.
//

import Foundation
import NIOCore


public struct MessageSequence: AsyncSequence {
    public typealias Element = SequenceResult
    
    
    let consumer: Consumer
    
    public init(consumer: Consumer) {
        self.consumer = consumer
    }
    
    public func makeAsyncIterator() -> Iterator {
        return MessageSequence.Iterator(consumer: consumer)
    }
    
    
}

extension MessageSequence {
    public struct Iterator: AsyncIteratorProtocol {
        
        public typealias Element = SequenceResult
        
        let consumer: Consumer
        
        init(consumer: Consumer) {
            self.consumer = consumer
        }
        
        mutating public func next() async throws -> SequenceResult? {
            let result = consumer.next()
                var res: SequenceResult?

                switch result {
                case .ready(let sequence):
                    res = .success(sequence!.0)
                case .preparing:
                    res = .retry
                }
               
                return res
        }
        
    }
}

public enum SequenceResult {
    case success(IRCMessage), retry
}

enum NextResult {
    case ready((IRCMessage, Bool)?), preparing
}

public enum ConsumedState {
    case consumed, waiting
}

public var consumedState = ConsumedState.consumed
var nextResult = NextResult.preparing

public final class Consumer {
    
    internal var wb = IRCMessageBuffer(CircularBuffer<IRCMessage>())
    
    public init() {}
    
    
    public func feedConsumer(_ messages: [IRCMessage]) {
        wb.append(contentsOf: messages)
    }
    
    func next() -> NextResult {
        switch consumedState {
        case .consumed:
            consumedState = .waiting
            let message = wb.removeFirst()
            if message.1 == false {
                return .preparing
            } else {
                return .ready(message)
            }
        case .waiting:
            return .preparing
        }
    }
}

internal struct IRCMessageBuffer {
    static internal let defaultBufferTarget = 256
    static internal let defaultBufferMinimum = 1
    static internal let defaultBufferMaximum = 16384

    internal let minimum: Int
    internal let maximum: Int

    internal var circularBuffer: CircularBuffer<IRCMessage>
    private var target: Int
    private var canShrink: Bool = false

    internal var isEmpty: Bool {
        self.circularBuffer.isEmpty
    }

    internal init(minimum: Int, maximum: Int, target: Int, buffer: CircularBuffer<IRCMessage>) {
        precondition(minimum <= target && target <= maximum)
        self.minimum = minimum
        self.maximum = maximum
        self.target = target
        self.circularBuffer = buffer
    }

    internal init(_ circularBuffer: CircularBuffer<IRCMessage>) {
        self.init(
            minimum: Self.defaultBufferMinimum,
            maximum: Self.defaultBufferMaximum,
            target: Self.defaultBufferTarget,
            buffer: circularBuffer
        )
    }

    mutating internal func append<Messages: Sequence>(contentsOf newMessages: Messages) where Messages.Element == IRCMessage {
        self.circularBuffer.append(contentsOf: newMessages)
        if self.circularBuffer.count >= self.target, self.canShrink, self.target > self.minimum {
            self.target &>>= 1
        }
        self.canShrink = true
    }

    /// Returns the next row in the FIFO buffer and a `bool` signalling if new rows should be loaded.
    mutating internal func removeFirst() -> (IRCMessage, Bool) {
        let element = self.circularBuffer.removeFirst()

        // If the buffer is drained now, we should double our target size.
        if self.circularBuffer.count == 0, self.target < self.maximum {
            self.target = self.target * 2
            self.canShrink = false
        }

        return (element, self.circularBuffer.count < self.target)
    }

    mutating internal func popFirst() -> (IRCMessage, Bool)? {
        guard !self.circularBuffer.isEmpty else {
            return nil
        }
        return self.removeFirst()
    }
}
