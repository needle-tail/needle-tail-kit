//
//  MessengerTransportBridge.swift
//
//
//  Created by Cole M on 1/15/24.
//

import CypherMessaging

protocol MessengerTransportBridge: Sendable {
    var ctcDelegate: CypherTransportClientDelegate? { get set }
    var ctDelegate: ClientTransportDelegate? { get set }
    var plugin: NeedleTailPlugin? { get set }
}
