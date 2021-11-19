//
//  File.swift
//  
//
//  Created by Cole M on 11/5/21.
//

import Foundation
import NIOIRC

public protocol IRCServiceDelegate {
    
    func resume()
    func suspend()
//    func conversationWithID(_ id: String) async throws -> IRCConversation?
//    func registerChannel(_ name: String) async throws -> IRCConversation?
    func unregisterChannel(_ name: String)
//    func registerDirectMessage(_ name: String) async throws -> IRCConversation?
//    func conversationsForRecipient(_ recipient: IRCMessageRecipient, create: Bool) async throws -> [ IRCConversation ]
//    func conversationsForRecipients(_ recipients: [ IRCMessageRecipient ], create: Bool) async throws -> [ IRCConversation ]
    func sendMessage(_ message: String, to recipient: IRCMessageRecipient) async -> Bool
}

public protocol IRCConversationDelegate {
    func sendMessage(_ message: String) async -> Bool
    func addMessage(_ message: String, from sender: IRCUserID) async
    func addNotice(_ message: String) async
}


public protocol ConnectionKitIRCStore {
    
    //    func fetchContacts() async throws -> [IRCAccountModel]
        func createTimeline(_ contact: TimelineEntryModel) async throws
    //    func updateContact(_ contact: IRCAccountModel) async throws
    //    func removeContact(_ contact: IRCAccountModel) async throws
    
    
//    func fetchAccounts() async throws -> [IRCAccountModel]
//    func createContact(_ contact: IRCAccountModel) async throws
//    func updateContact(_ contact: IRCAccountModel) async throws
//    func removeContact(_ contact: IRCAccountModel) async throws
//    
//    func fetchConversations() async throws -> [IRCConversationModel]
//    func createConversation(_ conversation: IRCConversationModel) async throws -> IRCConversation
//    func updateConversation(_ conversation: IRCConversationModel) async throws
//    func removeConversation(_ conversation: IRCConversationModel) async throws
    
//    func fetchDeviceIdentities() async throws -> [DeviceIdentityModel]
//    func createDeviceIdentity(_ deviceIdentity: DeviceIdentityModel) async throws
//    func updateDeviceIdentity(_ deviceIdentity: DeviceIdentityModel) async throws
//    func removeDeviceIdentity(_ deviceIdentity: DeviceIdentityModel) async throws
//
//    func fetchChatMessage(byId messageId: UUID) async throws -> ChatMessageModel
//    func fetchChatMessage(byRemoteId remoteId: String) async throws -> ChatMessageModel
//    func createChatMessage(_ message: ChatMessageModel) async throws
//    func updateChatMessage(_ message: ChatMessageModel) async throws
//    func removeChatMessage(_ message: ChatMessageModel) async throws
//    func listChatMessages(
//        inConversation: UUID,
//        senderId: Int,
//        sortedBy: SortMode,
//        minimumOrder: Int?,
//        maximumOrder: Int?,
//        offsetBy: Int,
//        limit: Int
//    ) async throws -> [ChatMessageModel]
//
//    func readLocalDeviceConfig() async throws -> Data
//    func writeLocalDeviceConfig(_ data: Data) async throws
//    func readLocalDeviceSalt() async throws -> String
//
//    func readJobs() async throws -> [JobModel]
//    func createJob(_ job: JobModel) async throws
//    func updateJob(_ job: JobModel) async throws
//    func removeJob(_ job: JobModel) async throws
}
