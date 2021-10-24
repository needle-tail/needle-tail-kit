//
//  File.swift
//  
//
//  Created by Cole M on 9/19/21.
//

import Foundation

extension IRCNIOHandler: Equatable {
    public static func == (lhs: IRCNIOHandler, rhs: IRCNIOHandler) -> Bool {
        return lhs === rhs
    }
}
