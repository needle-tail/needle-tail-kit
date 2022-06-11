//
//  NeedleTailQueue.swift
//  
//
//  Created by Cole M on 4/16/22.
//

import Foundation

public protocol NeedleTailQueue {
    associatedtype Element
    mutating func enqueue(_ element: Element?, elements: [Element]?) async
    mutating func dequeue() async -> Element?
    var isEmpty: Bool { get }
    var peek: Element? { get }
}


public struct NeedleTailStack<T>: NeedleTailQueue {
    
   public init() {}
    
    public var enqueueStack: [T] = []
    public var dequeueStack: [T] = []
    public var isEmpty: Bool {
        return dequeueStack.isEmpty && enqueueStack.isEmpty
    }
    
    
    public var peek: T? {
        return !dequeueStack.isEmpty ? dequeueStack.last : enqueueStack.first
    }
    
    
    public mutating func enqueue(_ element: T? = nil, elements: [T]? = nil) {
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
        
        if dequeueStack.isEmpty {
            dequeueStack = enqueueStack.reversed()
            enqueueStack.removeAll()
        }
        let pop = dequeueStack.popLast()
        return pop
    }
}
