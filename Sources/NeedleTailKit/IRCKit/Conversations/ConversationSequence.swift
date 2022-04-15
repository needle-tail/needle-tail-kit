//
//  ConversationSequence.swift
//  
//
//  Created by Cole M on 4/11/22.
//

import CypherMessaging

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
            let result = consumer.next()
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

public enum ConsumedState {
    case consumed, waiting
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

public final class ConversationConsumer {
    
    internal var wb = NeedleTailStack<TargetConversation.Resolved>()
    
    public init() {}
    
    
    public func feedConsumer(_ conversation: [TargetConversation.Resolved]) async {
        wb.enqueue(conversation)
    }
    
    func next() -> NextResult {
        switch dequeuedConsumedState {
        case .consumed:
            consumedState = .waiting
            guard let message = wb.dequeue() else { return .finished }
            return .ready(message)
        case .waiting:
            return .preparing
        }
    }
}

protocol NeedleTailQueue {
    associatedtype Element
    mutating func enqueue(_ elements: [Element])
    mutating func dequeue() -> Element?
    var isEmpty: Bool { get }
    var peek: Element? { get }
}

struct NeedleTailStack<T>: NeedleTailQueue {
    
    
    private var enqueueStack: [T] = []
    private var dequeueStack: [T] = []
    var isEmpty: Bool {
        return dequeueStack.isEmpty && enqueueStack.isEmpty
    }
    
    
    var peek: T? {
        return !dequeueStack.isEmpty ? dequeueStack.last : enqueueStack.first
    }
    
    
    mutating func enqueue(_ elements: [T]) {
        //If stack is empty we want to set the array to the enqueue stack
        if enqueueStack.isEmpty {
            dequeueStack = enqueueStack
        }
        //Then we append the element
        enqueueStack.append(contentsOf: elements)
    }
    
    
    @discardableResult
    mutating func dequeue() -> T? {
        
        if dequeueStack.isEmpty {
            dequeueStack = enqueueStack.reversed()
            enqueueStack.removeAll()
        }
        return dequeueStack.popLast()
    }
}
