//
//  File.swift
//  
//
//  Created by Cole M on 9/19/21.
//

import Foundation

/// Don't do that at home
extension String: IRCServicePasswordProvider {
    public func passwordForAccount(_ account: IRCAccount, yield: @escaping (IRCAccount, String) -> Void) {
        yield(account, self)
    }
}
