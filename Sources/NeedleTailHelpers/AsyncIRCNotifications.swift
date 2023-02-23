//
//  NeedleTailNotifications.swift
//
//
//  Created by Cole M on 5/17/22.
//


public protocol AsyncIRCNotificationsDelegate: AnyObject {
    func respond(to alert: AlertType) async
}

public enum AlertType: Equatable, Sendable {
    case registryRequest, registryRequestAccepted, registryRequestRejected, none
    
    public static func == (lhs: AlertType, rhs: AlertType) -> Bool {
        switch (lhs, rhs) {
        case (.registryRequest, .registryRequest), (.registryRequestAccepted, .registryRequestAccepted), (.registryRequestRejected, .registryRequestRejected), (.none, .none):
            return true
        default:
            return false
        }
    }
}
