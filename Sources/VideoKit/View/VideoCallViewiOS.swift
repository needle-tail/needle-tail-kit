//
//  VideoCalView.swift
//  VideoKit (iOS)
//
//  Created by Cole M on 9/26/21.
//

#if os(iOS)
import UIKit
import AVKit


public class VideoCallViewiOS: UIView {
    
    public let previewView: UIView = {
        let view = UIView()
        view.frame = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        return view
    }()
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    var sampleBufferVideoCallView = SampleBufferVideoCallViewiOS()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.commonInit()
        
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    fileprivate func commonInit() {
        buildRemoteView()
        buildLocalView()
    }
    
    deinit {
        print("Memory Reclaimed in MasterView")
    }
    
    func buildRemoteView() {
        addSubview(sampleBufferVideoCallView)
        sampleBufferVideoCallView.anchors(top: topAnchor, leading: leadingAnchor, bottom: bottomAnchor, trailing: trailingAnchor, paddingTop: -50, paddingLeft: -40, paddingBottom: -40, paddingRight: -40, width: 0, height: 0)
    }

    func buildLocalView() {
        sampleBufferVideoCallView.addSubview(previewView)
        previewView.anchors(top: nil, leading: nil, bottom: sampleBufferVideoCallView.bottomAnchor, trailing: sampleBufferVideoCallView.trailingAnchor, paddingTop: 0, paddingLeft: 0, paddingBottom: 40, paddingRight: 70 ,width: 1080 / 8, height: 1920 / 8)
    }
}
#endif
