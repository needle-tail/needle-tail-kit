//
//  NeedleTailQueue.swift
//  
//
//  Created by Cole M on 4/16/22.
//

import Foundation


public protocol NeedleTailQueue {
    associatedtype Element
    mutating func enqueue(_ elements: [Element])
    mutating func dequeue() -> Element?
    var isEmpty: Bool { get }
    var peek: Element? { get }
}


public struct NeedleTailStack<T>: NeedleTailQueue {
    
   public init() {}
    
    private var enqueueStack: [T] = []
    private var dequeueStack: [T] = []
    public var isEmpty: Bool {
        return dequeueStack.isEmpty && enqueueStack.isEmpty
    }
    
    
    public var peek: T? {
        return !dequeueStack.isEmpty ? dequeueStack.last : enqueueStack.first
    }
    
    
    public mutating func enqueue(_ elements: [T]) {
        //If stack is empty we want to set the array to the enqueue stack
        if enqueueStack.isEmpty {
            dequeueStack = enqueueStack
        }
        //Then we append the element
        enqueueStack.append(contentsOf: elements)
    }
    
    
    @discardableResult
    public mutating func dequeue() -> T? {
        
        if dequeueStack.isEmpty {
            dequeueStack = enqueueStack.reversed()
            enqueueStack.removeAll()
        }
        return dequeueStack.popLast()
    }
}
