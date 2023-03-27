//
//  Token.swift
//
//
//  Created by Cole M on 6/18/22.
//

import JWTKit

public struct Token: JWTPayload, @unchecked Sendable {
    public let device: NTKUser
    public let exp: ExpirationClaim
    
    public init(
        device: NTKUser,
        exp: ExpirationClaim
    ) {
        self.device = device
        self.exp = exp
    }
    
    public func verify(using signer: JWTSigner) throws {
        try exp.verifyNotExpired()
    }
}
