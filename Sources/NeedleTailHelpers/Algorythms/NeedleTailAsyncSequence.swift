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
                    return .success(sequence.item)
                case .consumed:
                    return nil
                }
            } onCancel: {
                stateMachine.cancel()
            }
        }
    }
}
public struct TaskJob<T> {
    public var item: T
    public var priority: Priority
}
public enum Priority: Int, Sendable {
    case urgent, standard, background, utility
}
public actor NeedleTailAsyncConsumer<T> {
    
    public var deque = Deque<TaskJob<T>>()
    public var stateMachine = NTASequenceStateMachine()
    
    public init(deque: Deque<TaskJob<T>> = Deque<TaskJob<T>>()) {
        self.deque = deque
    }
    
    public func feedConsumer(_ item: T, priority: Priority = .standard) async {
        print("Fed task with priority: ", priority)
        switch priority {
        case .urgent:
            deque.prepend(TaskJob(
                item: item,
                priority: priority
            )
            )
        case .standard:
            if let utilityIndex = deque.firstIndex(where: { $0.priority == .utility }) {
                deque.insert(
                    TaskJob(
                        item: item,
                        priority: priority
                    )
                    , at: utilityIndex)
            } else {
                deque.append(TaskJob(
                    item: item,
                    priority: priority
                )
                )
            }
        case .utility:
            if let backgroundIndex = deque.firstIndex(where: { $0.priority == .background }) {
                deque.insert(
                    TaskJob(
                        item: item,
                        priority: priority
                    )
                    , at: backgroundIndex)
            } else {
                deque.append(TaskJob(
                    item: item,
                    priority: priority
                )
                )
            }
        case .background:
            deque.append(TaskJob(
                item: item,
                priority: priority
            )
            )
        }
    }
    
    public func next() async -> NTASequenceStateMachine.NextNTAResult<TaskJob<T>> {
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
    
    public func ready() {
        state = 1
    }
    
    public func cancel() {
        state = 0
    }
}
