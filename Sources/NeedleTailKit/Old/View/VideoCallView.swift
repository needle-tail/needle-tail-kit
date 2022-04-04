//
//  VideoCallView.swift
//  VideoKit
//
//  Created by Cole M on 10/2/21.
// Copyright © 2021 Cole M. All rights reserved.
//

#if os(macOS)
import Cocoa
import AVKit

public class VideoCallView: NSView {
    
public let previewView: NSView = {
        let view = NSView()
        return view
    }()
    
    public var previewLayer: AVCaptureVideoPreviewLayer?
    public let sampleBufferVideoCallView = SampleBufferVideoCallView()
    

    override private init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()

    }

    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    fileprivate func commonInit() {
        frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)
        buildLocalView()
        buildRemoteView()
    }
    
    deinit {
        print("Memory Reclaimed in VideoCallView")
    }
    
    
    private func buildRemoteView() {
        addSubview(sampleBufferVideoCallView)
    }

    private func buildLocalView() {
        sampleBufferVideoCallView.addSubview(previewView)
    }
}

#endif
