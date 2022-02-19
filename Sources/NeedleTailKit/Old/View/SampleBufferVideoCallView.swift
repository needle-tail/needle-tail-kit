//
//  PreviewView.swift
//  VideoKit
//
//  Created by Cole M on 10/2/21.
//  Copyright © 2021 Cole M. All rights reserved.
//

#if os(macOS)
import Cocoa
import AVFoundation


public class SampleBufferVideoCallView: NSView {
    
    public override func makeBackingLayer() -> AVSampleBufferDisplayLayer {
        return AVSampleBufferDisplayLayer()
    }

    weak var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer? {
        return layer as? AVSampleBufferDisplayLayer
    }
}
#endif
