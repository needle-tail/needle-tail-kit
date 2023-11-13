//
//  NeedleTailAsyncSequence.swift
//  
//
//  Created by Cole M on 6/9/23.
//

import DequeModule
import Atomics

public struct NeedleTailAsyncSequence<ConsumerTypeValue>: AsyncSequence {

    public typealias Element = NTASequenceStateMachine.NTASequenceResult<ConsumerTypeValue>
    
    public let consumer: NeedleTailAsyncConsumer<ConsumerTypeValue>
    
    public init(consumer: NeedleTailAsyncConsumer<ConsumerTypeValue>) {
        self.consumer = consumer
    }
    
    public func makeAsyncIterator() -> Iterator<ConsumerTypeValue> {
        return NeedleTailAsyncSequence.Iterator(consumer: consumer)
    }
    
    
}

extension NeedleTailAsyncSequence {
    public struct Iterator<T>: AsyncIteratorProtocol {
        
        public typealias Element = NTASequenceStateMachine.NTASequenceResult<T>
        
        public let consumer: NeedleTailAsyncConsumer<T>
        
        public init(consumer: NeedleTailAsyncConsumer<T>) {
            self.consumer = consumer
        }
        
        public func next() async throws -> NTASequenceStateMachine.NTASequenceResult<T>? {
            let stateMachine = await consumer.stateMachine
            return await withTaskCancellationHandler {
                let result = await consumer.next()
                switch result {
                case .ready(let sequence):
                   return .success(sequence)
                case .finished:
                   return .finished
                }
            } onCancel: {
                stateMachine.cancel()
            }
        }
    }
}
   
public actor NeedleTailAsyncConsumer<T> {
    
    public var deque = Deque<T>()
    public var stateMachine = NTASequenceStateMachine()
    
    public init(deque: Deque<T> = Deque<T>()) {
        self.deque = deque
    }
    
    public func feedConsumer(_ items: [T]) async {
        deque.append(contentsOf: items)
    }
    
    public func next() async -> NTASequenceStateMachine.NextNTAResult<T> {
        switch stateMachine.state {
        case 0:
            guard let item = deque.popFirst() else { return .finished }
            return .ready(item)
        case 1:
            return .finished
        default:
            return .finished
        }
    }
}

public final class NTASequenceStateMachine: Sendable {
    
    public init() {}
    
    public enum NTAConsumedState: Int, Sendable, CustomStringConvertible {
        case consumed, waiting
        
        public var description: String {
                switch self.rawValue {
                case 0:
                    return "consumed"
                case 1:
                    return "waiting"
                default:
                    return ""
                }
            }
        }
    
    public enum NTASequenceResult<T: Sendable>: Sendable {
        case success(T), finished
    }

    public enum NextNTAResult<T: Sendable>: Sendable {
        case ready(T), finished
    }
    
    private let protectedState = ManagedAtomic<Int>(NTAConsumedState.consumed.rawValue)
     
    public var state: NTAConsumedState.RawValue {
        get { protectedState.load(ordering: .acquiring) }
        set { protectedState.store(newValue, ordering: .relaxed) }
    }

    func cancel() {
        state = 0
    }
}
