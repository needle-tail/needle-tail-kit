//
//  VideoCallViewController+OutputSampleBufferDelegate.swift
//  VideoKit
//
//  Created by Cole M on 9/25/21.
//  Copyright © 2021 Cole M. All rights reserved.
//
#if os(iOS) || os(macOS)
#if os(macOS)
import Cocoa
#else
import UIKit
#endif
import AVKit
import NIOCore


protocol InboundMediaDelegate: AnyObject {
    func receiveRemoteCapture(_ buffer: CMSampleBuffer)
}

protocol OutboundMediaDelegate {
    func transportLocalCapture(_ buffer: CMSampleBuffer)
}

protocol VideoCallDelegegate {
    func setSessionPreset(sessionPreset: AVCaptureSession.Preset?)
}

extension VideoCallController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, VideoCallDelegegate {
    
    
    func setSessionPreset(sessionPreset: AVCaptureSession.Preset?) {
        self.captureSession.sessionPreset = sessionPreset ?? .medium
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
#if os(iOS)
        if #available(iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
            if connection.isVideoOrientationSupported {
                switch UIDevice.current.orientation{
                case .portrait:
                    connection.videoOrientation = .portrait
                case .portraitUpsideDown:
                    connection.videoOrientation = .portrait
                case .landscapeLeft:
                    connection.videoOrientation = .landscapeRight
                case .landscapeRight:
                    connection.videoOrientation = .landscapeLeft
                default:
                    connection.videoOrientation = .portrait
                }
            }
        }
#endif
        captureLocalOutput(sampleBuffer)
        receiveRemoteCapture(sampleBuffer)
    }
    
    func captureLocalOutput(_ buffer: CMSampleBuffer) {
//        guard let videoPixelBuffer = CMSampleBufferGetImageBuffer(buffer),
//              let formatDescription = CMSampleBufferGetFormatDescription(buffer) else {
//                  return
//              }
        self.seriviceManager.transportLocalCapture(buffer)
    }
    
    func receiveRemoteCapture(_ buffer: CMSampleBuffer) {
        enqueueRemoteCapture(buffer: buffer)
    }

    
    
    
    func enqueueRemoteCapture(buffer: CMSampleBuffer) {
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
#if os(iOS)
            if #available(iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
                strongSelf.videoCallView.sampleBufferVideoCallView.sampleBufferDisplayLayer?.enqueue(buffer)
                strongSelf.videoCallView.sampleBufferVideoCallView.sampleBufferDisplayLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
            }
#else
            strongSelf.videoCallView.sampleBufferVideoCallView.sampleBufferDisplayLayer?.enqueue(buffer)
            print(strongSelf.videoCallView.sampleBufferVideoCallView.sampleBufferDisplayLayer?.hasSufficientMediaDataForReliablePlaybackStart as Any, "RELIABLE?")
            strongSelf.videoCallView.sampleBufferVideoCallView.sampleBufferDisplayLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
#endif
        }
    }
}
#endif
