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
    internal let seriviceManager: NIOServiceManager
#if os(iOS)
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
    internal let videoCallView: VideoCallView
    internal let defaultDevices = AVCaptureDevice.DiscoverySession(
        deviceTypes: [
            .builtInMicrophone,
            .builtInWideAngleCamera
        ],
        mediaType: .video,
        position: .front
    )
#endif
    internal enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    internal let elg: EventLoopGroup
    
    internal init(elg: EventLoopGroup, videoCallView: VideoCallView) {
        self.elg = elg
        self.videoCallView = videoCallView
        self.seriviceManager = NIOServiceManager()
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

    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    deinit {
        print("Memory Reclaimed in VideoCallController")
        if self.setupResult == .success {
            self.captureSession.stopRunning()
            self.isSessionRunning = self.captureSession.isRunning
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
    
  
    
    internal func openSocket() {
            self.reactToSetup()
    }
    
    internal func closeSocket() {
        DispatchQueue.main.async {
            if self.setupResult == .success && self.captureSession.isRunning {
                self.videoCallView.sampleBufferVideoCallView.sampleBufferDisplayLayer?.flushAndRemoveImage()
            self.captureSession.stopRunning()

            self.isSessionRunning = self.captureSession.isRunning
            do {
            try self.elg.syncShutdownGracefully()
            } catch {
                print("Error shutting down ELG: \(error)")
            }
            }
        }
    }
}

