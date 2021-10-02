//
//  VideoCallViewController.swift
//  VideoKit
//
//  Created by Cole M on 10/02/21.
//  Copyright © 2021 Cole M. All rights reserved.
//
#if os(iOS)
import UIKit
#else
import Cocoa
#endif
import AVKit
import NIO


internal class VideoCallController: NSObject, InboundMediaDelegate {
    
    internal let captureSession = AVCaptureSession()
    internal var captureDevice: AVCaptureDevice?
    internal let videoDataOutput = AVCaptureVideoDataOutput()
    internal var setupResult: SessionSetupResult = .success
    internal var isSessionRunning = false
    internal var videoInput: AVCaptureDeviceInput!
    internal var sessionPreset: AVCaptureSession.Preset = .high
#if os(iOS)
    internal let videoCallView: VideoCallViewiOS?
    internal let defaultDevices = AVCaptureDevice.DiscoverySession(
        deviceTypes: [
            .builtInDualCamera,
            .builtInMicrophone,
            .builtInWideAngleCamera
        ],
        mediaType: .video,
        position: .front
    )
#else
    internal let videoCallView: VideoCallView?
    internal let defaultDevices = AVCaptureDevice.DiscoverySession(
        deviceTypes: [
            .builtInMicrophone,
            .builtInWideAngleCamera
        ],
        mediaType: .video,
        position: .front
    )
#endif

    
    
    internal let seriviceManager: NIOServiceManager
    internal enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    internal let elg: EventLoopGroup
    
    internal init(elg: EventLoopGroup) {
        self.elg = elg
        self.seriviceManager = NIOServiceManager()
        
#if os(iOS)
        self.videoCallView = VideoCallViewiOS()
#else
        self.videoCallView = VideoCallView()
#endif
        
        super.init()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera
            break
            
        case .notDetermined:

            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
            })
            
        default:
            // The user has previously denied access
            setupResult = .notAuthorized
        }
        
    }
    
    func reactToSetup() {
        
        let sessionPromise = self.elg.next().makePromise(of: Void.self)

        switch self.setupResult {
        case .success:
            self.createRemoteCapture(promise: sessionPromise)
        case .notAuthorized:
            print("NO AUTH")
            sessionPromise.fail(VideoKitErrors.failedSesson)
        case .configurationFailed:
            print("Config Failed")
            sessionPromise.fail(VideoKitErrors.failedSesson)
        }
        
    }
    
    enum VideoKitErrors: Swift.Error {
        case failedSesson
        case failedCapture
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    deinit {
        if self.setupResult == .success {
            self.captureSession.stopRunning()
            self.isSessionRunning = self.captureSession.isRunning
        }
    }
    
  
    
    internal func openSocket() {
            self.reactToSetup()
    }
    
    internal func closeSocket() {
        if self.setupResult == .success && captureSession.isRunning {
            self.captureSession.stopRunning()
            self.videoCallView?.previewLayer?.removeFromSuperlayer()
            self.videoCallView?.previewLayer = nil
            self.videoCallView?.sampleBufferVideoCallView.sampleBufferDisplayLayer.flushAndRemoveImage()
            self.videoCallView?.sampleBufferVideoCallView.removeFromSuperview()
            self.videoCallView?.previewView.removeFromSuperview()
            self.isSessionRunning = self.captureSession.isRunning
            do {
            try self.elg.syncShutdownGracefully()
            } catch {
                print("Error shutting down ELG: \(error)")
            }
        }
    }
}

