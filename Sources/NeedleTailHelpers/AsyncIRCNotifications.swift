//
//  NeedleTailNotifications.swift
//  
//
//  Created by Cole M on 5/17/22.
//
#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS))
import Foundation
import Combine

public protocol AsyncIRCNotificationsDelegate: AnyObject {
    func respond(to alert: AlertType) async 
}

public enum AlertType {
    case registryRequest, registryRequestAccepted, registryRequestRejected
}

open class AsyncIRCNotifications {
    public init() {}
    public let received = PassthroughSubject<AlertType, Never>()
}
#endif
