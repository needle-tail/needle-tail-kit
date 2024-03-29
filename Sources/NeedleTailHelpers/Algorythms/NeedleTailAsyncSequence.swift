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
                case .consumed:
                    return nil
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
        if !deque.isEmpty {
            stateMachine.ready()
        } else {
            stateMachine.cancel()
        }
        switch stateMachine.state {
        case 0:
            return .consumed
        case 1:
            guard let item = deque.popFirst() else { return .consumed }
            return .ready(item)
        default:
            return .consumed
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
                    //Empty consumer
                    return "consumed"
                case 1:
                    //Non Empty consumer
                    return "ready"
                default:
                    return ""
                }
            }
        }
    
    public enum NTASequenceResult<T: Sendable>: Sendable {
        case success(T), consumed
    }

    public enum NextNTAResult<T: Sendable>: Sendable {
        case ready(T), consumed
    }
    
    private let protectedState = ManagedAtomic<Int>(NTAConsumedState.consumed.rawValue)
     
    public var state: NTAConsumedState.RawValue {
        get { protectedState.load(ordering: .acquiring) }
        set { protectedState.store(newValue, ordering: .relaxed) }
    }
    
    func ready() {
        state = 1
    }

    func cancel() {
        state = 0
    }
}
