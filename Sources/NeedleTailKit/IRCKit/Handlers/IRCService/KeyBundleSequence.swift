//
//  File.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import Foundation
import CypherMessaging

public struct KeyBundleSequence: AsyncSequence {
    public typealias Element = UserConfig
    
    let bundle: UserConfig
    
    /// - Parameters:
    /// - bundle: UserConfig
    init(
        bundle: UserConfig
    ) {
        self.bundle = bundle
    }
    
    public func makeAsyncIterator() -> KeyBundleIterator {
        return KeyBundleIterator(
            bundle: bundle
        )
    }
}


public struct KeyBundleIterator: AsyncIteratorProtocol {
    
    public typealias Element = UserConfig
    
    let bundle: UserConfig
    
    /// - Parameters:
    /// - bundle: UserConfig
    init(
        bundle: UserConfig
    ) {
        self.bundle = bundle
    }
    
    mutating public func next() async throws -> UserConfig? {
        return bundle
    }
}

extension UserConfig: Equatable {
    public static func == (lhs: UserConfig, rhs: UserConfig) -> Bool {
        return lhs.identity.data == rhs.identity.data
    } 
}
