////
////  NIOBackPressuredStreamSourceDelegate.swift
////  
////
////  Created by Cole M on 10/16/22.
////
//
//import NIOCore
//
//public final class NIOBackPressuredStreamSourceDelegate: NIOAsyncSequenceProducerDelegate, @unchecked Sendable {
//    public var produceMoreCallCount = 0
//    public var produceMoreHandler: (() -> Void)?
//    public func produceMore() {
//        self.produceMoreCallCount += 1
//        if let produceMoreHandler = self.produceMoreHandler {
//            return produceMoreHandler()
//        }
//    }
//    
//    public var didTerminateCallCount = 0
//    public var didTerminateHandler: (() -> Void)?
//    public func didTerminate() {
//        self.didTerminateCallCount += 1
//        if let didTerminateHandler = self.didTerminateHandler {
//            return didTerminateHandler()
//        }
//    }
//    
//    public init() {}
//}
