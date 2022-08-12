//
//  Token.swift
//  
//
//  Created by Cole M on 6/18/22.
//

import Foundation
@preconcurrency import JWTKit

public struct Token: JWTPayload, Sendable {
    public let device: UserDeviceId
    public let exp: ExpirationClaim
    
    public init(
        device: UserDeviceId,
        exp: ExpirationClaim
    ) {
        self.device = device
        self.exp = exp
    }
    
    public func verify(using signer: JWTSigner) throws {
        try exp.verifyNotExpired()
    }
}
