//
//  ConversationSequence.swift
//
//
//  Created by Cole M on 4/11/22.
//

import CypherMessaging
import MessagingHelpers
import NeedleTailHelpers
import DequeModule

public struct NeedleTailAsyncSequence<T>: AsyncSequence {
    public typealias Element = NTASequenceResult<T>
    
    
    public let consumer: NeedleTailAsyncConsumer<T>
    
    public init(consumer: NeedleTailAsyncConsumer<T>) {
        self.consumer = consumer
    }
    
    public func makeAsyncIterator() -> Iterator<T> {
        return NeedleTailAsyncSequence.Iterator(consumer: consumer)
    }
    
    
}

extension NeedleTailAsyncSequence {
    public struct Iterator<T>: AsyncIteratorProtocol {
        
        public typealias Element = NTASequenceResult<T>
        
        public let consumer: NeedleTailAsyncConsumer<T>
        
        public init(consumer: NeedleTailAsyncConsumer<T>) {
            self.consumer = consumer
        }
        
        public func next() async throws -> NTASequenceResult<T>? {
            let result = await consumer.next()
            var res: NTASequenceResult<T>?
            switch result {
            case .ready(let sequence):
                res = .success(sequence)
            case .preparing:
                res = .retry
            case .finished:
                res = .finished
            }
            
            return res
        }
    }
}

public enum NTASequenceResult<T> {
    case success(T), retry, finished
}

public enum NextNTAResult<T> {
    case ready(T) , preparing, finished
}
 
var ntaState = ConsumedState.consumed
var ntaConsumedState = ConsumedState.consumed
public var dequeuedConsumedState = ConsumedState.consumed
   
public actor NeedleTailAsyncConsumer<T> {
    
    public var deque = Deque<T>()
    
    public func feedConsumer(_ items: [T]) async {
        deque.append(contentsOf: items)
    }
    
    public func next() async -> NextNTAResult<T> {
        switch dequeuedConsumedState {
        case .consumed:
            consumedState = .waiting
            guard let item = deque.popFirst() else { return .finished }
            return .ready(item)
        case .waiting:
            return .preparing
        }
    }
}
