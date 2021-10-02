import NIO
import NIOTransportServices
import AVKit
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

public final class VideoCallKit {
    
    internal let eventLoopGroup: EventLoopGroup
    internal let videoCallController: VideoCallController
    
    public init() {
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        self.eventLoopGroup = NIOTSEventLoopGroup()
#else
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
#endif
        self.videoCallController = VideoCallController(elg: self.eventLoopGroup)
    }
    
#if os(macOS)
    public func returnCallView() -> NSView? {
        guard let vcv = self.videoCallController.videoCallView else { return nil }
        return vcv
    }
#else
    public func returnCallView() -> UIView? {
        guard let vcv = self.videoCallController.videoCallView else { return nil }
        return vcv
    }
#endif
    
    
    public func makeCall() {
        self.videoCallController.openSocket()
    }
    
    public func endCall() {
        self.videoCallController.closeSocket()
    }
    
    
    
    public func videoQuality(quality: AVCaptureSession.Preset) {
        self.videoCallController.setSessionPreset(sessionPreset: quality)
    }

    
    
    
    
    
    
    
    
    
    
    
    
    
}
