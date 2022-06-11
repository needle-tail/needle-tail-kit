//
//  ParserSeqeuence.swift
//  
//
//  Created by Cole M on 3/28/22.
//

import Foundation


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
            let result = await consumer.next()
                var res: ParseSequenceResult?
                switch result {
                case .ready(let sequence):
                    res = .success(sequence)
                case .finished:
                    res = .finished
                }
                return res
        }
        
    }
}

public enum ConsumedState {
    case consumed, waiting
}

public enum ParseSequenceResult {
    case success(String), finished
}

enum NextParseResult {
    case ready(String), finished
}



public var consumedState = ConsumedState.consumed
public var parseConsumedState = ConsumedState.consumed
var nextParseResult = NextParseResult.finished

public final class ParseConsumer {
    
    public var stack = NeedleTailStack<String>()
    
    public init() {}
    

    public func feedConsumer(_ conversation: String) {
        stack.enqueue(conversation)
    }
    
    func next() async -> NextParseResult {
        switch parseConsumedState {
        case .consumed:
            consumedState = .waiting
            guard let message = stack.dequeue() else { return .finished }
            return .ready(message)
        case .waiting:
            return .finished
        }
    }
}
