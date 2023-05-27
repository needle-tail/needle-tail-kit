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

struct NeedleTailAsyncSequence<T>: AsyncSequence {
    typealias Element = NTASequenceResult<T>
    
    
    let consumer: NeedleTailAsyncConsumer<T>
    
    init(consumer: NeedleTailAsyncConsumer<T>) {
        self.consumer = consumer
    }
    
    func makeAsyncIterator() -> Iterator<T> {
        return NeedleTailAsyncSequence.Iterator(consumer: consumer)
    }
    
    
}

extension NeedleTailAsyncSequence {
    struct Iterator<T>: AsyncIteratorProtocol {
        
        typealias Element = NTASequenceResult<T>
        
        let consumer: NeedleTailAsyncConsumer<T>
        
        init(consumer: NeedleTailAsyncConsumer<T>) {
            self.consumer = consumer
        }
        
        func next() async throws -> NTASequenceResult<T>? {
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

enum NTASequenceResult<T> {
    case success(T), retry, finished
}

enum NextNTAResult<T> {
    case ready(T) , preparing, finished
}
 
var ntaState = ConsumedState.consumed
var ntaConsumedState = ConsumedState.consumed
public var dequeuedConsumedState = ConsumedState.consumed
   
actor NeedleTailAsyncConsumer<T> {
    
    var deque = Deque<T>()
    
    func feedConsumer(_ items: [T]) async {
        deque.append(contentsOf: items)
    }
    
    func next() async -> NextNTAResult<T> {
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
