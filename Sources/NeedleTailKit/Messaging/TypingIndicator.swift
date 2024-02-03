import Combine
import SwiftUI
import CypherMessaging
import NeedleTailHelpers
import Collections

struct ClientsKnownAquaintances {
    var contacts = OrderedSet<NeedleTailNick>()
    func isTyping(_ contact: Contact, stream: NeedleTailStream) -> Bool {
        return false
    }
}

final class AquaintanceInfo: ObservableObject {

    var aquaintances: ClientsKnownAquaintances?
    
//    @Published var typingContacts = Set<Contact>()
//    private var clients = [NeedleTailClient]()
//    var cancellables = Set<AnyCancellable>()
//    private var isTyping = false
//    let priorityActor = PriorityActor()
//
//    func emitIsTyping(_ isTyping: Bool) async {
//        if self.isTyping == isTyping {
//            return
//        }
//
//        self.isTyping = isTyping
//        var flags = P2PStatusMessage.StatusFlags()
//        if isTyping {
//            flags.insert(.isTyping)
//        }
//
//        for client in clients {
//            _ = try? await client.updateStatus(flags: flags)
//        }
//    }
//
    
    func deduceContacts() {
        
        
    }
    
    @PriorityActor
    private func addAquaintance<Chat: AnyConversation>(_ client: NeedleTailClient, for chat: Chat) async throws {
//        let contacts = try await chat.messenger.listContacts()
//        aquaintances?.contacts.append(contact)
//        clients.append(client)
//                if
//                    let contact = try? await chat.messenger.createContact(byUsername: client.configuration.ntkUser.username),
//                    let status = client.remoteStatus
//                {
//                    await self.changeStatus(for: contact, to: status)
//                }
        
//        client.onDisconnect { [weak self] in
//            guard
//                let indicator = self
//            else {
//                return
//            }
//            
//            indicator.clients.removeAll { $0 === client }
//            
//            Task { @PriorityActor [weak self] in
//                guard let self else { return }
//                    if let contact = try? await chat.messenger.createContact(byUsername: client.username) {
//                        indicator.typingContacts.remove(contact)
//                    }
//                }
//            }
        
//        client.onStatusChange { [weak self] status in
//            guard
//                let indicator = self,
//                let status = status
//            else { return }
//
//            Task { @PriorityActor [weak self] in
//                    if let contact = try? await chat.messenger.createContact(byUsername: client.username) {
//                        await indicator.changeStatus(for: contact, to: status)
//                    }
//                }
//            }
        }
    
    @MainActor
    private func changeStatus(for contact: Contact, to status: P2PStatusMessage) {
            if status.flags.contains(.isTyping) {
//                self.typingContacts.insert(contact)
            } else {
//                self.typingContacts.remove(contact)
            }
        }
    
//    init<Chat: AnyConversation>(chat: Chat) {
////        Task { @PriorityActor in
////            await priorityActor.queueThrowingAction() {
////                let clients = try await chat.listOpenP2PConnections()
////                for client in clients {
////                    self.addClient(client, for: chat)
////                }
////                //            emitter.p2pClientConnected.sink { [weak self] client in
////                //                if chat.conversation.members.contains(client.username) {
////                //                    self?.addClient(client, for: chat)
////                //                }
////                //            }.store(in: &self.cancellables)
////                try await chat.buildP2PConnections()
////            }
////        }
//    }
}
