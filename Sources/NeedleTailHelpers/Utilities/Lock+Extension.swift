//
//  Lock+Extension.swift
//
//
//  Created by Cole M on 7/7/22.
//

import NIOConcurrencyHelpers

extension NIOLock: @unchecked Sendable {
    @inlinable
    public func withSendableLock<T: Sendable>(_ body: () throws -> T) rethrows -> T {
        self.lock()
        defer {
            self.unlock()
        }
        return try body()
    }
    
    @inlinable
    public func withSendableAsyncLock<T: Sendable>(_ body: () async throws -> T) async rethrows -> T {
        self.lock()
        defer {
            self.unlock()
        }
        return try await body()
    }
}
