//
//  NeedleTailNotifications.swift
//  
//
//  Created by Cole M on 5/17/22.
//

import Foundation
#if canImport(Combine)
import Combine
#endif

public protocol AsyncIRCNotificationsDelegate: AnyObject {
    func respond(to alert: AlertType) async 
}

#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS))
open class AsyncIRCNotifications {
    public init() {}
    public let received = PassthroughSubject<AlertType, Never>()
}
#endif

public enum AlertType {
    case registryRequest, registryRequestAccepted, registryRequestRejected
}
