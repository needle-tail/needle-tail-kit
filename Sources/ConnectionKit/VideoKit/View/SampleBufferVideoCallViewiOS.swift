//
//  SampleBufferVideoCallView.swift
//  CartisimRTCiOSSample (iOS)
//
//  Created by Cole M on 9/26/21.
//

#if os(iOS)
import UIKit
import AVFoundation

public class SampleBufferVideoCallViewiOS: UIView {
   public override class var layerClass: AnyClass {
        get { return AVSampleBufferDisplayLayer.self }
    }

    weak var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer? {
        return layer as? AVSampleBufferDisplayLayer
    }
}
#endif
