//
//  ParserSeqeuence.swift
//  
//
//  Created by Cole M on 3/28/22.
//

import Foundation
import NIOCore


public struct ParserSequence: AsyncSequence {
    public typealias Element = ParseSequenceResult
    
    
    let consumer: ParseConsumer
    
    public init(consumer: ParseConsumer) {
        self.consumer = consumer
    }
    
    public func makeAsyncIterator() -> Iterator {
        return ParserSequence.Iterator(consumer: consumer)
    }
    
    
}

extension ParserSequence {
    public struct Iterator: AsyncIteratorProtocol {
        
        public typealias Element = ParseSequenceResult
        
        let consumer: ParseConsumer
        
        init(consumer: ParseConsumer) {
            self.consumer = consumer
        }
        
        mutating public func next() async throws -> ParseSequenceResult? {
            let result = consumer.next()
                var res: ParseSequenceResult?
            print("RESULT____", result)
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

public enum ConsumedState {
    case consumed, waiting
}

public enum ParseSequenceResult {
    case success(ParseMessageTask), retry
}

enum NextParseResult {
    case ready((ParseMessageTask, Bool)?), preparing
}

public var consumedState = ConsumedState.consumed
public var parseConsumedState = ConsumedState.consumed
var nextParseResult = NextParseResult.preparing

public final class ParseConsumer {
    
    internal var wb = MessageBuffer(CircularBuffer<String>())
    
    public init() {}
    
    
    public func feedConsumer(_ messages: [String]) async {
        wb.append(contentsOf: messages)
    }
    
    func next() -> NextParseResult {
        switch parseConsumedState {
        case .consumed:
            consumedState = .waiting
            let message = wb.removeFirst()
            if message.1 == false {
                return .preparing
            } else {
                let task = (ParseMessageTask(message: message.0), false)
                return .ready(task)
            }
        case .waiting:
            return .preparing
        }
    }
}

internal struct MessageBuffer {
    static internal let defaultBufferTarget = 256
    static internal let defaultBufferMinimum = 1
    static internal let defaultBufferMaximum = 16384

    internal let minimum: Int
    internal let maximum: Int

    internal var circularBuffer: CircularBuffer<String>
    private var target: Int
    private var canShrink: Bool = false

    internal var isEmpty: Bool {
        self.circularBuffer.isEmpty
    }

    internal init(minimum: Int, maximum: Int, target: Int, buffer: CircularBuffer<String>) {
        precondition(minimum <= target && target <= maximum)
        self.minimum = minimum
        self.maximum = maximum
        self.target = target
        self.circularBuffer = buffer
    }

    internal init(_ circularBuffer: CircularBuffer<String>) {
        self.init(
            minimum: Self.defaultBufferMinimum,
            maximum: Self.defaultBufferMaximum,
            target: Self.defaultBufferTarget,
            buffer: circularBuffer
        )
    }

    mutating internal func append<Messages: Sequence>(contentsOf newMessages: Messages) where Messages.Element == String {
        self.circularBuffer.append(contentsOf: newMessages)
        if self.circularBuffer.count >= self.target, self.canShrink, self.target > self.minimum {
            self.target &>>= 1
        }
        self.canShrink = true
    }

    /// Returns the next row in the FIFO buffer and a `bool` signalling if new rows should be loaded.
    mutating internal func removeFirst() -> (String, Bool) {
        let element = self.circularBuffer.removeFirst()

        // If the buffer is drained now, we should double our target size.
        if self.circularBuffer.count == 0, self.target < self.maximum {
            self.target = self.target * 2
            self.canShrink = false
        }

        return (element, self.circularBuffer.count < self.target)
    }

    mutating internal func popFirst() -> (String, Bool)? {
        guard !self.circularBuffer.isEmpty else {
            return nil
        }
        return self.removeFirst()
    }
}
