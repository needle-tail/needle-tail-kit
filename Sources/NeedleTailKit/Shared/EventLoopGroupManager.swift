//import NIO
//import NIOTransportServices
//import NIOSSL
//import Network
//
///// `EventLoopGroupManager` can be used to manage an `EventLoopGroup`, either by creating or by sharing an existing one.
/////
///// When making network client libraries with SwiftNIO that are supposed to work well on both Apple platforms (macOS,
///// iOS, tvOS, ...) as well as Linux, users often find it tedious to select the right combination of:
/////
///// - an `EventLoopGroup`
///// - a bootstrap
///// - a TLS implementation
/////
///// The choices to the above need to be compatible, or else the program won't work.
/////
///// What makes the task even harder is that as a client library, you often want to share the `EventLoopGroup` with other
///// components. That raises the question of how to choose a bootstrap and a matching TLS implementation without even
///// knowing the concrete `EventLoopGroup` type (it may be `SelectableEventLoop` which is an internal `NIO` types).
///// `EventLoopGroupManager` should support all those use cases with a simple API.
//public class EventLoopGroupManager {
//    private var group: Optional<EventLoopGroup>
//    private let provider: Provider
//    
//    private var sslContext = try! NIOSSLContext(configuration: .makeClientConfiguration())
//    
//    public enum Provider {
//        case createNew
//        case shared(EventLoopGroup)
//    }
//    
//    /// Initialize the `EventLoopGroupManager` with a `Provder` of `EventLoopGroup`s.
//    ///
//    /// The `Provider` lets you choose whether to use a `.shared(group)` or to `.createNew`.
//    public init(provider: Provider) {
//        self.provider = provider
//        switch self.provider {
//        case .shared(let group):
//            self.group = group
//        case .createNew:
//            self.group = nil
//        }
//    }
//    
//    deinit {
//        assert(self.group == nil, "Please call EventLoopGroupManager.syncShutdown .")
//    }
//}
//
//// - MARK: Public API
//extension EventLoopGroupManager {
//    /// Create a "universal bootstrap" for the given host.
//    ///
//    /// - parameters:
//    ///     - hostname: The hostname to connect to (for SNI).
//    ///     - useTLS: Whether to use TLS or not.
//    public func makeBootstrap(hostname: String, useTLS: Bool = true) throws -> NIOClientBootstrap {
//        let bootstrap: NIOClientBootstrap
//        
//        if let group = self.group {
//            bootstrap = try self.makeUniversalBootstrapWithExistingGroup(group, serverHostname: hostname)
//        } else {
//            bootstrap = try self.makeUniversalBootstrapWithSystemDefaults(serverHostname: hostname)
//        }
//        
//        if useTLS {
//            return bootstrap.enableTLS()
//        } else {
//            return bootstrap
//        }
//    }
//    
//    public func makeUDPBootstrap(hostname: String, useTLS: Bool = true) throws -> NIOClientBootstrap {
//        let bootstrap: NIOClientBootstrap
//        if let group = self.group {
//            bootstrap = try self.makeUniversalUDPBootstrapWithExistingGroup(group, serverHostname: hostname)
//        } else {
//            bootstrap = try self.makeUniversalUDPBootstrapWithSystemDefaults(serverHostname: hostname)
//        }
//        
//        if useTLS {
//            return bootstrap.enableTLS()
//        } else {
//            return bootstrap
//        }
//    }
//    
//    /// Shutdown the `EventLoopGroupManager`.
//    ///
//    /// This will release all resources associated with the `EventLoopGroupManager` such as the threads that the
//    /// `EventLoopGroup` runs on.
//    ///
//    /// This method _must_ be called when you're done with this `EventLoopGroupManager`.
//    public func syncShutdown() throws {
//        switch self.provider {
//        case .createNew:
//            try self.group?.syncShutdownGracefully()
//        case .shared:
//            () // nothing to do.
//        }
//        self.group = nil
//    }
//}
//
//// - MARK: Error types
//extension EventLoopGroupManager {
//    /// The provided `EventLoopGroup` is not compatible with this client.
//    public struct UnsupportedEventLoopGroupError: Swift.Error {
//        var eventLoopGroup: EventLoopGroup
//    }
//}
//
//// - MARK: Internal functions
//extension EventLoopGroupManager {
//    // This function combines the right pieces and returns you a "universal client bootstrap"
//    // (`NIOClientTCPBootstrap`). This allows you to bootstrap connections (with or without TLS) using either the
//    // NIO on sockets (`NIO`) or NIO on Network.framework (`NIOTransportServices`) stacks.
//    // The remainder of the code should be platform-independent.
//    private func makeUniversalBootstrapWithSystemDefaults(serverHostname: String) throws -> NIOClientTCPBootstrap {
//        if let group = self.group {
//            return try self.makeUniversalBootstrapWithExistingGroup(group, serverHostname: serverHostname)
//        }
//        return try self.makeUniversalBootstrapWithExistingGroup(self.group!, serverHostname: serverHostname)
//    }
//    
//    // If we already know the group, then let's just contruct the correct bootstrap.
//    private func makeUniversalBootstrapWithExistingGroup(_ group: EventLoopGroup,
//                                                         serverHostname: String) throws -> NIOClientBootstrap {
//        if let bootstrap = ClientBootstrap(validatingGroup: group) {
//            return try NIOClientTCPBootstrap(bootstrap,
//                                             tls: NIOSSLClientTLSProvider(context: self.sslContext,
//                                                                          serverHostname: serverHostname))
//        }
//        
//#if canImport(Network)
//        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 6, *) {
//            if let makeBootstrap = NIOTSConnectionBootstrap(validatingGroup: group) {
//                
//                return NIOClientBootstrap(makeBootstrap, tls: NIOTSClientTLSProvider())
//            }
//        }
//#endif
//        
//        throw UnsupportedEventLoopGroupError(eventLoopGroup: group)
//    }
//    
//    
//    private func makeUniversalUDPBootstrapWithSystemDefaults(serverHostname: String) throws -> NIOClientBootstrap {
//        return try self.makeUniversalUDPBootstrapWithExistingGroup(self.group!, serverHostname: serverHostname)
//    }
//    
//    
//    private func makeUniversalUDPBootstrapWithExistingGroup(_
//                                                            group: EventLoopGroup,
//                                                            serverHostname: String
//    ) throws -> NIOClientBootstrap {
//        if let bootstrap = DatagramBootstrap(validatingGroup: group) {
//            return try NIOClientBootstrap(
//                bootstrap,
//                tls: NIOSSLClientTLSProvider(
//                    context: self.sslContext,
//                    serverHostname: serverHostname
//                ))
//        }
//        
//#if canImport(Network)
//        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 6, *) {
//            return NIOClientBootstrap(NIOTSDatagramBootstrap(group: group), tls: NIOTSDatagramTLSProvider())
//        }
//#endif
//        
//        throw UnsupportedEventLoopGroupError(eventLoopGroup: group)
//        
//    }
//    
//}
//
