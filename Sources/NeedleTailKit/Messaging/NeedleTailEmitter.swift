//
//  NeedleTailEmitter.swift
//
//
//  Created by Cole M on 4/21/22.
//

import CypherMessaging
 import NeedleTailHelpers

@NeedleTailTransportActor
public enum ServerConnectionState {
    case registering, registered, deregistering, deregistered
}

@MainActor
public final class NeedleTailEmitter: NSObject {
    public static let shared = NeedleTailEmitter()
#if (os(macOS) || os(iOS))
    
    @Published public var cypher: CypherMessenger?
    @Published public var username: Username = Username("")
    @Published public var deviceId: DeviceId = DeviceId()
    
    @Published public var channelIsActive = false
//    @Published public var clientIsRegistered = false
    @Published public var connectionState = ServerConnectionState.deregistered
    
    @Published public var messageReceived: AnyChatMessage?
    @Published public var messageRemoved: AnyChatMessage?
    @Published public var messageChanged: AnyChatMessage?
    @Published public var metadataChanged: AnyChatMessage?
    @Published public var multipartReceived: Data?
    @Published public var multipartUploadComplete: Bool?
    @Published public var multipartDownloadFailed: MultipartDownloadFailed = MultipartDownloadFailed(status: false, error: "")
    @Published public var listedFilenames = [Filename]()
    
    @Published public var contactChanged: Contact?
    @Published public var registered = false
    @Published public var contactAdded: Contact?
    @Published public var contactRemoved: Contact?
    @Published public var nicksOnline: [NeedleTailNick] = []
    @Published public var partMessage = ""
    @Published public var chatMessageChanged: AnyChatMessage?
    @Published public var needleTailNick: NeedleTailNick?
    @Published public var requestMessageId: String?
    @Published public var qrCodeData: Data?
    @Published public var accountExists: String = ""
    @Published public var showScanner: Bool = false
    @Published public var dismissRegistration: Bool = false
    @Published public var showProgress: Bool = false
    @Published public var transportState: TransportState.State = .clientOffline
    
    @Published public var conversationChanged: AnyConversation?
    @Published public var conversationAdded: AnyConversation?
    @Published public var contactToDelete: Contact?
    @Published public var contactToUpdate: Contact?
    @Published public var deleteContactAlert: Bool = false
    @Published public var clearChatAlert: Bool = false
    @Published public var groupChats = [GroupChat]()
    @Published public var bundles = ContactsBundle()
    @Published public var readReceipts = false
    @Published public var salt = ""
    @Published public var destructionTime: DestructionMetadata?
    //    = UserDefaults.standard.integer(forKey: "destructionTime"
#endif
}

#if (os(macOS) || os(iOS))
extension NeedleTailEmitter: ObservableObject {}
#endif
