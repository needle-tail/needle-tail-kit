//
//  Blob.swift
//  
//
//  Created by Cole M on 7/2/22.
//

import Foundation
import CypherMessaging

public struct Blob<C: Codable>: Codable {
    public let _id: String
    public let creator: Username
    public var document: C
}
