//
//  ConversationSequence.swift
//  
//
//  Created by Cole M on 4/11/22.
//

import CypherMessaging
import MessagingHelpers
import NeedleTailHelpers
import NeedleTailProtocol

public struct ConversationSequence: AsyncSequence {
    public typealias Element = SequenceResult
    
    
    let consumer: ConversationConsumer
    
    public init(consumer: ConversationConsumer) {
        self.consumer = consumer
    }
    
    public func makeAsyncIterator() -> Iterator {
        return ConversationSequence.Iterator(consumer: consumer)
    }
    
    
}

extension ConversationSequence {
    public struct Iterator: AsyncIteratorProtocol {
        
        public typealias Element = SequenceResult
        
        let consumer: ConversationConsumer
        
        init(consumer: ConversationConsumer) {
            self.consumer = consumer
        }
        
        mutating public func next() async throws -> SequenceResult? {
            let result = await consumer.next()
            var res: SequenceResult?
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

public enum SequenceResult {
    case success(TargetConversation.Resolved), retry, finished
}

enum NextResult {
    case ready(TargetConversation.Resolved) , preparing, finished
}

public var consumedState = ConsumedState.consumed
public var dequeuedConsumedState = ConsumedState.consumed
var nextResult = NextResult.preparing

@NeedleTailTransportActor
public final class ConversationConsumer {
    
    internal var stack = NeedleTailStack<TargetConversation.Resolved>()
    
    public init() {}
    
    public func feedConsumer(_ conversation: [TargetConversation.Resolved]) async {
        await stack.enqueue(elements: conversation)
    }
    
    func next() async -> NextResult {
        switch dequeuedConsumedState {
        case .consumed:
            consumedState = .waiting
            guard let message = await stack.dequeue() else { return .finished }
            return .ready(message)
        case .waiting:
            return .preparing
        }
    }
}

