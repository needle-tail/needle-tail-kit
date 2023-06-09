//
//  MOTDBuilder.swift
//  
//
//  Created by Cole M on 6/9/23.
//

import NIOConcurrencyHelpers

public final class MOTDBuilder: @unchecked Sendable {

    private var intitialMessage = ""
    private var bodyMessage = ""
    private var endMessage = ""
    private var finalMessage = ""
    private let lock = NIOLock()
    
    public func createInitial(message: String) {
        lock.withLock {
            intitialMessage = message
        }
    }
    
    public func createBody(message: String) {
        lock.withLock {
            bodyMessage = message
        }
    }
    
    public func createFinalMessage() -> String {
        return lock.withLock {
            intitialMessage + bodyMessage
        }
    }
    
    public func clearMessage() {
        lock.withLock {
            intitialMessage = ""
            bodyMessage = ""
        }
    }
}
