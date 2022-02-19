//
//  File.swift
//  
//
//  Created by Cole M on 10/2/21.
//

#if os(iOS) || os(macOS)
import Foundation
import NIO
import AVKit


extension VideoCallController {
    
    internal func createLocalCapture(promise: EventLoopPromise<Void>) {
        
        if !captureSession.isRunning {
            print("Starting Capture Session")
            captureSession.sessionPreset = self.sessionPreset
 
            
            // Find the FaceTime HD camera object
            _ = defaultDevices.devices.map { dev in
                if dev.hasMediaType(.video) {
                    self.captureDevice = dev
                } else {
                    self.setupResult = .configurationFailed
                }
            }
            
            guard let d = captureDevice else { return }
            do {
                self.videoInput = try AVCaptureDeviceInput(device: d)
                
                self.captureSession.removeInput(self.videoInput)
                
                if self.captureSession.canAddInput(self.videoInput) {
                    
                    captureSession.addInput(self.videoInput)
                    
                    self.videoCallView.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
                    self.videoCallView.previewLayer?.videoGravity = .resizeAspectFill
                    
                    //Local Capture setup
                    guard let p = self.videoCallView.previewLayer else { return }
#if os(macOS)
                    
                    self.videoCallView.previewView.layer?.masksToBounds = true
                    self.videoCallView.previewView.layer?.cornerRadius = 8
                    self.videoCallView.previewLayer?.frame = self.videoCallView.previewView.bounds
                    self.videoCallView.previewView.layer?.addSublayer(p)
#else
                    
                    self.videoCallView.previewView.layer.masksToBounds = true
                    self.videoCallView.previewView.layer.cornerRadius = 8
                    self.videoCallView.previewLayer?.frame = videoCallView.previewView.bounds
                    self.videoCallView.previewView.layer.addSublayer(p)
                    
#endif
                    captureSession.commitConfiguration()
                    
                    // Start camera
                    captureSession.startRunning()
                    self.isSessionRunning = self.captureSession.isRunning
                }
                promise.succeed(())
            } catch {
                print(AVCaptureSessionErrorKey.description)
                setupResult = .configurationFailed
                captureSession.commitConfiguration()
                promise.fail(error)
            }
        } else {
            print("Capture Session already running")
            promise.fail(VideoKitErrors.failedCapture)
        }
    }
    
    func createRemoteCapture(promise: EventLoopPromise<Void>) {
        if setupResult != .success {
            return
        }
        
        captureSession.beginConfiguration()
        // Add a video data output
        
        self.captureSession.removeOutput(videoDataOutput)
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoDataOutput.setSampleBufferDelegate(self, queue: .global(qos: .background))
            promise.succeed(())
        } else {
            print("Could not add video data output to the session")
            setupResult = .configurationFailed
            captureSession.commitConfiguration()
            promise.fail(VideoKitErrors.failedCapture)
            return
        }
        
        let localCapturePromise = self.group.next().makePromise(of: Void.self)
        self.createLocalCapture(promise: localCapturePromise)
    }
}
#endif
