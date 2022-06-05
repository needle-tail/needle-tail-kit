import ArgumentParser
import Foundation
import NIO
import CypherMessaging
import Crypto
import Logging
import AsyncIRC
import NeedleTailHelpers
import MessagingHelpers
#if canImport(Network)
import NIOTransportServices
#endif

public final class IRCService {
    
    var cypher: CypherMessenger?
    var messenger: IRCMessenger?
    var client: IRCClient?
    var transportState: TransportState
    var clientInfo: ClientContext.ServerClientInfo
    var waitCount = 0
    var logger: Logger
    var authenticated: AuthenticationState?
    public let signer: TransportCreationRequest
    public var conversations: [DecryptedModel<ConversationModel>]?
    
    public init(
        signer: TransportCreationRequest,
        authenticated: AuthenticationState,
        transportState: TransportState,
        clientInfo: ClientContext.ServerClientInfo,
        delegate: CypherTransportClientDelegate?
    ) async {
        self.logger = Logger(label: "IRCService - ")
        self.signer = signer
        self.authenticated = authenticated
        self.transportState = transportState
        self.clientInfo = clientInfo
        
        let activeClientOptions = self.clientOptionsForAccount(signer, clientInfo: clientInfo)
        guard let context = activeClientOptions else { return }
        self.client = IRCClient(
            cypher: cypher,
            clientContext: context,
            transportState: transportState,
            transportDelegate: delegate)
    }
    
    
    private func clientOptionsForAccount(_
                                         signer: TransportCreationRequest,
                                         clientInfo: ClientContext.ServerClientInfo
    ) -> ClientContext? {
        let lowerCasedName = signer.username.raw.replacingOccurrences(of: " ", with: "").ircLowercased()
//        let nick = NeedleTailNick(deviceId: signer.deviceId, name: lowerCasedName)
        guard let nick = NeedleTailNick(deviceId: signer.deviceId, name: lowerCasedName) else {
            return nil
        }
        return ClientContext(
            clientInfo: clientInfo,
            nickname: nick
        )
    }
}

