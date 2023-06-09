//
//  NeedleTailQueue.swift
//
//
//  Created by Cole M on 4/16/22.
//

public protocol NeedleTailQueue: Sendable {
    associatedtype Element
    func enqueue(_ element: Element?, elements: [Element]?) async
    func dequeue() async -> Element?
    func popFirst() async -> Element?
    func drain() async
    func isEmpty() async -> Bool
    func peek() async -> Element?
}


public actor NeedleTailStack<T: Sendable>: NeedleTailQueue, Sendable  {
    
    public init() {}
    
    public var enqueueStack: [T] = []
    public var dequeueStack: [T] = []

    public func isEmpty() async -> Bool {
        return dequeueStack.isEmpty && enqueueStack.isEmpty
    }
    
    public func peek() async -> T? {
        return !dequeueStack.isEmpty ? dequeueStack.last : enqueueStack.first
    }

    public func enqueue(_ element: T? = nil, elements: [T]? = nil) async {
        consumptionState = .enquing
        //If stack is empty we want to set the array to the enqueue stack
        if enqueueStack.isEmpty {
            dequeueStack = enqueueStack
        }
        //Then we append the element
        if let element = element {
        enqueueStack.append(element)
        } else if let elements = elements {
            enqueueStack.append(contentsOf: elements)
        }
    }

    public func dequeue() async -> T? {
        consumptionState = .draining
        if dequeueStack.isEmpty {
            dequeueStack = enqueueStack.reversed()
            enqueueStack.removeAll()
        }
        if !dequeueStack.isEmpty {
            return dequeueStack.popLast()
        } else {
            consumptionState = .ready
            return nil
        }
    }
    
    public func popFirst() async -> T? {
        consumptionState = .draining
        
        if dequeueStack.isEmpty {
            dequeueStack = enqueueStack.reversed()
            enqueueStack.removeAll()
        }
        if !dequeueStack.isEmpty {
            return dequeueStack.first
        } else {
            consumptionState = .ready
            return nil
        }
    }

    
    public func drain() async {
        enqueueStack.removeAll()
        dequeueStack.removeAll()
    }
}

public enum ConsumptionState: Sendable {
    case consuming, enquing, dequing, draining, ready, empty
}
public var consumptionState = ConsumptionState.empty

public protocol SyncQueue: Sendable {
    associatedtype Element
    mutating func enqueue(_ element: Element?, elements: [Element]?)
    mutating func dequeue() -> Element?
    mutating func popFirst() -> Element?
    mutating func drain()
    mutating func isEmpty() -> Bool
    mutating func peek() -> Element?
}


public struct SyncStack<T: Sendable>: SyncQueue, Sendable  {
    
    public init() {}
    
    public var enqueueStack: [T] = []
    public var dequeueStack: [T] = []

    public mutating func isEmpty() -> Bool {
        return dequeueStack.isEmpty && enqueueStack.isEmpty
    }
    
    public mutating func peek() -> T? {
        return !dequeueStack.isEmpty ? dequeueStack.last : enqueueStack.first
    }

    public mutating func enqueue(_ element: T? = nil, elements: [T]? = nil) {
        consumptionState = .enquing
        //If stack is empty we want to set the array to the enqueue stack
        if enqueueStack.isEmpty {
            dequeueStack = enqueueStack
        }

        //Then we append the element
        if let element = element {
        enqueueStack.append(element)
        } else if let elements = elements {
            enqueueStack.append(contentsOf: elements)
        }
    }
    
    public mutating func dequeue() -> T? {
        consumptionState = .draining
        if dequeueStack.isEmpty {
            dequeueStack = enqueueStack.reversed()
            enqueueStack.removeAll()
        }
        
        if !dequeueStack.isEmpty {
            return dequeueStack.popLast()
        } else {
            consumptionState = .ready
            return nil
        }
    }
    
    public mutating func popFirst() -> T? {
        consumptionState = .draining
        
        if dequeueStack.isEmpty {
            dequeueStack = enqueueStack.reversed()
            enqueueStack.removeAll()
        }
        if !dequeueStack.isEmpty {
            return dequeueStack.first
        } else {
            consumptionState = .ready
            return nil
        }
    }

    
    public mutating func drain() {
        enqueueStack.removeAll()
        dequeueStack.removeAll()
    }
}
