//
//  File.swift
//  
//
//  Created by Cole M on 10/10/21.
//

import Foundation

extension NIOHandler: Equatable {
    public static func == (lhs: NIOHandler, rhs: NIOHandler) -> Bool {
        return lhs === rhs
    }
}
