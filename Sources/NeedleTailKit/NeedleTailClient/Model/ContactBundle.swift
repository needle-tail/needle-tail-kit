//
//  ContactsBundle.swift
//  
//
//  Created by Cole M on 9/4/23.
//

import CypherMessaging
 import NeedleTailHelpers

#if (os(macOS) || os(iOS))
public final class ContactsBundle: ObservableObject {
    
    @Published public var contactListBundle: ContactBundle?
    @Published public var contactBundle: ContactBundle?
    @Published public var contactBundleViewModel = [ContactBundle]()
    @Published public var scrollToBottom: UUID?
    
    public struct ContactBundle: Equatable, Hashable, Identifiable {
        public let id = UUID()
        public var contact: Contact
        public var privateChat: PrivateChat
        public var groupChats: [GroupChat]
        public var cursor: AnyChatMessageCursor
        public var messages: [NeedleTailMessage]
        public var mostRecentMessage: MostRecentMessage<PrivateChat>?
        internal var sortedBy: ContactListSorted = .unPinRead
        
        public init(
            contact: Contact,
            privateChat: PrivateChat,
            groupChats: [GroupChat],
            cursor: AnyChatMessageCursor,
            messages: [NeedleTailMessage],
            mostRecentMessage: MostRecentMessage<PrivateChat>? = nil
        ) {
            self.contact = contact
            self.privateChat = privateChat
            self.groupChats = groupChats
            self.cursor = cursor
            self.messages = messages
            self.mostRecentMessage = mostRecentMessage
        }
        
        public static func == (lhs: ContactBundle, rhs: ContactBundle) -> Bool {
            return lhs.id == rhs.id
        }
        
        public func hash(into hasher: inout Hasher) {
            id.hash(into: &hasher)
        }
        
        @MainActor
        public func isPinned() -> Bool {
            privateChat.isPinned
        }
        
        @MainActor
        public func isMarkedUnread() -> Bool {
            privateChat.isMarkedUnread
        }
    }
    
    internal enum ContactListSorted: Comparable {
        case unRead, pinned, unPinRead
    }
    
    
    
    @MainActor
    public func arrangeBundle() {
        var storedContacts = contactBundleViewModel
        contactBundleViewModel.removeAll()
        
        for bundle in storedContacts {
            var bundle = bundle
            if bundle.isPinned() && !bundle.isMarkedUnread() {
                bundle.sortedBy = .pinned
            } else if bundle.isPinned() && bundle.isMarkedUnread() {
                bundle.sortedBy = .unRead
            } else if !bundle.isPinned() && bundle.isMarkedUnread() {
                bundle.sortedBy = .unRead
            } else if !bundle.isPinned() && !bundle.isMarkedUnread() {
                bundle.sortedBy = .unPinRead
            }
            contactBundleViewModel.append(bundle)
        }
        
        var indexOfUnread = 0
        var lastUnread = 0
        
        for setBundle in contactBundleViewModel {
            guard let index = contactBundleViewModel.firstIndex(where: { $0.contact.username == setBundle.contact.username }) else { return }
            switch setBundle.sortedBy {
            case .unRead:
                contactBundleViewModel.move(fromOffsets: IndexSet(integer: index), toOffset: indexOfUnread)
                indexOfUnread += 1
                lastUnread = indexOfUnread
            case .pinned:
                contactBundleViewModel.move(fromOffsets: IndexSet(integer: index), toOffset:lastUnread + 1)
            case .unPinRead:
                contactBundleViewModel.move(fromOffsets: IndexSet(integer: index), toOffset: contactBundleViewModel.count)
            }
        }
        storedContacts.removeAll()
    }
}
#endif
