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
    
    public var previewLayer: AVCaptureVideoPreviewLayer?
    public var sampleBufferVideoCallView = SampleBufferVideoCallViewiOS()
    
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
    }

    func buildLocalView() {
        sampleBufferVideoCallView.addSubview(previewView)
    }
}
#endif
