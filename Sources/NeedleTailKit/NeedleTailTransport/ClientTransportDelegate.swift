//
//  ClientTransportDelegate.swift
//  
//
//  Created by Cole M on 1/15/24.
//

import Foundation

protocol ClientTransportDelegate: AnyObject, Sendable {
    func shutdown() async
}
