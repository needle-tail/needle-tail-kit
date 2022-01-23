//
//  NIOServiceManager.swift
//  VideoKit
//
//  Created by Cole M on 9/23/21.
//  Copyright © 2021 Cole M. All rights reserved.
//
#if os(iOS) || os(macOS)
import Foundation
import AVKit


final class NIOServiceManager: OutboundMediaDelegate {
    
    internal weak var delegate: InboundMediaDelegate?
    
    init() {
        
    }
    
    deinit {
        print("Memory reclaimed in NIOServiceManager")
    }
    
    func transportLocalCapture(_ buffer: CMSampleBuffer) {
        print(buffer)
        delegate?.receiveRemoteCapture(buffer)
    }
}
#endif
