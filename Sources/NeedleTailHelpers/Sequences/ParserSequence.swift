//
//  ParserSeqeuence.swift
//  
//
//  Created by Cole M on 3/28/22.
//

import Foundation


public struct ParserSequence: AsyncSequence, Sendable {
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
    
    public struct Iterator: AsyncIteratorProtocol, Sendable {
        
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

public enum ConsumedState: Sendable {
    case consumed, waiting
}

public enum ParseSequenceResult: Sendable {
    case success(String), finished
}

enum NextParseResult: Sendable {
    case ready(String), finished
}

public enum ConsumptionState: Sendable {
    case consuming, enquing, dequing, draining, ready
}


public var consumedState = ConsumedState.consumed
public var parseConsumedState = ConsumedState.consumed
var nextParseResult = NextParseResult.finished
public var consumptionState = ConsumptionState.ready

@ParsingActor
public final class ParseConsumer {
    
    public var stack = NeedleTailStack<String>()
    public var count = 0
    
    public init() {}
    

    public func feedConsumer(_ strings: [String]) async {
        consumptionState = .consuming
        await stack.enqueue(nil , elements: strings)
        count = await stack.enqueueStack.count
    }
    
    func next() async -> NextParseResult {
        switch parseConsumedState {
        case .consumed:
            consumedState = .waiting
            guard let message = await stack.dequeue() else { return .finished }
            return .ready(message)
        case .waiting:
            return .finished
        }
    }
}

