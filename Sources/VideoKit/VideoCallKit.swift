import NIO
import NIOTransportServices
import AVKit
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

public final class VideoCallKit {
    
    internal static var eventLoopGroup: EventLoopGroup?
    internal var videoCallController: VideoCallController?
#if os(iOS)
//    internal let videoCallView: VideoCallViewiOS?
    
    public init(videoCallView: VideoCallViewiOS) throws {
        guard let elg = VideoCallKit.eventLoopGroup else { throw VideoKitErrors.nilEventLoopGroup }
        self.videoCallController = VideoCallController(elg: elg, videoCallView: videoCallView)
    }
    
    
    public class func initializeView(videoCallView: VideoCallViewiOS) throws -> VideoCallKit {
        var vck: VideoCallKit?
        do {
        vck = try VideoCallKit(videoCallView: videoCallView)
        } catch {
            print(VideoKitErrors.nilEventLoopGroup.rawValue)
        }
        guard let v = vck else { throw VideoKitErrors.nilVideoCallView }
        return v
    }
    
    
#else
//    private let videoCallView: VideoCallView?
    
    public init(videoCallView: VideoCallView) throws {
        guard let elg = VideoCallKit.eventLoopGroup else { throw VideoKitErrors.nilEventLoopGroup }
        self.videoCallController = VideoCallController(elg: elg, videoCallView: videoCallView)
    }
    
    
    public class func initializeView(videoCallView: VideoCallView) throws -> VideoCallKit {
        var vck: VideoCallKit?
        do {
        vck = try VideoCallKit(videoCallView: videoCallView)
        } catch {
            print(VideoKitErrors.nilEventLoopGroup.rawValue)
        }
        guard let v = vck else { throw VideoKitErrors.nilVideoCallView }
        return v
    }
    
    
#endif


    deinit {
        print("Memory Reclaimed VideoCallKit")
    }
    
    public class func startSession() {
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        VideoCallKit.eventLoopGroup = NIOTSEventLoopGroup(loopCount: System.coreCount, defaultQoS: .utility)
#else
        VideoCallKit.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
#endif
    }
    
    public func makeCall() {
        self.videoCallController?.openSocket()
    }
    
    public func endCall() {
        self.videoCallController?.closeSocket()
    }
    
    
    
    public func videoQuality(quality: AVCaptureSession.Preset) {
        self.videoCallController?.setSessionPreset(sessionPreset: quality)
    }

    
    
    
    
    
    
    
    
    
    
    
    
    
}
