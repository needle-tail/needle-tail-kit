//
//  ClientTransportDelegate.swift
//  
//
//  Created by Cole M on 1/15/24.
//

import Foundation

#if (os(macOS) || os(iOS))
protocol ClientTransportDelegate: AnyObject, Sendable {
    func shutdown() async
}
#endif
