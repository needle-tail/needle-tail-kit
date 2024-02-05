//
//  MultipartDownloadFailed.swift
//  
//
//  Created by Cole M on 9/4/23.
//

import Foundation

public struct ErrorReporter {
    public var status: Bool
    public var error: String
    
    public init(status: Bool, error: String) {
        self.status = status
        self.error = error
    }
}
