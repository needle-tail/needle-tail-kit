////
////  AsyncWriterDelegate.swift
////  
////
////  Created by Cole M on 10/16/22.
////
//
//import NIOCore
//import DequeModule
//
//public final class AsyncWriterDelegate: NIOAsyncWriterSinkDelegate, @unchecked Sendable {
//    public typealias Element = IRCMessage
//    
//    public var didYieldCallCount = 0
//    public var didYieldHandler: ((Deque<IRCMessage>) -> Void)?
//    public func didYield(contentsOf sequence: Deque<IRCMessage>) {
//        self.didYieldCallCount += 1
//        if let didYieldHandler = self.didYieldHandler {
//            didYieldHandler(sequence)
//        }
//    }
//    
//    public var didTerminateCallCount = 0
//    public var didTerminateHandler: ((Error?) -> Void)?
//    public func didTerminate(error: Error?) {
//        self.didTerminateCallCount += 1
//        if let didTerminateHandler = self.didTerminateHandler {
//            didTerminateHandler(error)
//        }
//    }
//}
