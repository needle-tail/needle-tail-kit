#if os(iOS) || os(macOS)
import NIO
import AVKit
#if os(macOS)
import Cocoa
#else
import UIKit
#endif
#if canImport(Network)
import NIOTransportServices
#endif

public final class VideoCallKit {
    
    internal static var group: EventLoopGroup?
    internal var videoCallController: VideoCallController?
#if os(iOS)
//    internal let videoCallView: VideoCallViewiOS?
    
    public init(videoCallView: VideoCallViewiOS) throws {
        guard let group = VideoCallKit.group else { throw VideoKitErrors.nilEventLoopGroup }
        self.videoCallController = VideoCallController(group: group, videoCallView: videoCallView)
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
        guard let group = VideoCallKit.group else { throw VideoKitErrors.nilEventLoopGroup }
        self.videoCallController = VideoCallController(group: group, videoCallView: videoCallView)
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
        VideoCallKit.group = NIOTSEventLoopGroup()
#else
        VideoCallKit.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
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
#endif
