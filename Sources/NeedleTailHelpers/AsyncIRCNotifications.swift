//
//  NeedleTailNotifications.swift
//  
//
//  Created by Cole M on 5/17/22.
//

import Foundation

public protocol AsyncIRCNotificationsDelegate: AnyObject {
    func respond(to alert: AlertType) async 
}

public enum AlertType {
    case registryRequest, registryRequestAccepted, registryRequestRejected, none
}
