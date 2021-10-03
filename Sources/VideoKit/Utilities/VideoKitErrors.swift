//
//  File.swift
//  
//
//  Created by Cole M on 10/3/21.
//

import Foundation

internal enum VideoKitErrors: String, Swift.Error {
    case nilEventLoopGroup          = "You need to call Start Session before initializing the View"
    case nilVideoCallView           = "You need to pass the VideoCallView"
}
