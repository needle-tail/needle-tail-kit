//
//  File.swift
//  
//
//  Created by Cole M on 10/10/21.
//

import Foundation

public protocol PasswordProvider {
    func passwordForAccount(_ account: MKAccount, yield: @escaping ( MKAccount, String ) -> Void)
}

/// Don't do that at home
extension String: PasswordProvider {
    public func passwordForAccount(_ account: MKAccount, yield: @escaping (MKAccount, String) -> Void) {
        yield(account, self)
    }
}
