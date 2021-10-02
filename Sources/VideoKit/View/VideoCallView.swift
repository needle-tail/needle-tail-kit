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
    
    internal var previewLayer: AVCaptureVideoPreviewLayer?
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
        print("Memory Reclaimed in MasterView")
    }
    
    
    private func buildRemoteView() {
        addSubview(sampleBufferVideoCallView)
        sampleBufferVideoCallView.anchors(top: topAnchor, leading: leadingAnchor, bottom: bottomAnchor, trailing: trailingAnchor, paddingTop: 0, paddingLeft: 0, paddingBottom: 0, paddingRight: 0, width: 0, height: 0)
    }

    private func buildLocalView() {
        sampleBufferVideoCallView.addSubview(previewView)
        previewView.anchors(top: nil, leading: nil, bottom: sampleBufferVideoCallView.bottomAnchor, trailing: sampleBufferVideoCallView.trailingAnchor, paddingTop: 0, paddingLeft: 0, paddingBottom: 20, paddingRight: 20, width: 300, height: 169)
    }
}

#endif
