//
//  ContactsBundle.swift
//
//
//  Created by Cole M on 9/4/23.
//

import CypherMessaging
import NeedleTailHelpers

public final class ContactsBundle {
    public static let shared = ContactsBundle()
    
#if (os(macOS) || os(iOS))
    @Published public var contactBundleViewModel = [ContactBundle]()
    @Published public var contactBundle: ContactBundle?
#else
    public var contactBundleViewModel = [ContactBundle]()
#endif
    
    enum Errors: Error {
        case cannotFindBundle
    }
    
    public init(contactBundleViewModel: [ContactBundle] = [ContactBundle]()) {
        self.contactBundleViewModel = contactBundleViewModel
    }
    
    public func findContactBundle(for username: String) async throws -> ContactBundle {
        guard let contactBundle = await contactBundleViewModel.async.first(where: { await $0.contact?.username.raw == username }) else { throw Errors.cannotFindBundle }
        return contactBundle
    }
    
    public struct ContactBundle: Equatable, Hashable, Identifiable {
        public var id = UUID()
        public var contact: Contact?
        public var chat: AnyConversation
        public var groupChats: [GroupChat]
        public var cursor: AnyChatMessageCursor
        public var messages: [NeedleTailMessage]
        public var mostRecentMessage: MostRecentMessage<PrivateChat>?
        internal var sortedBy: ContactListSorted = .unPinRead
        
        public init(
            contact: Contact? = nil,
            chat: AnyConversation,
            groupChats: [GroupChat],
            cursor: AnyChatMessageCursor,
            messages: [NeedleTailMessage],
            mostRecentMessage: MostRecentMessage<PrivateChat>? = nil
        ) {
            self.contact = contact
            self.chat = chat
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
            chat.isPinned()
        }
        
        @MainActor
        public func isMarkedUnread() -> Bool {
            chat.isMarkedUnread
        }
        
        @MainActor
        public func isPrivate() -> Bool {
            chat is PrivateChat
        }
        
        @MainActor
        public func isInternal() -> Bool {
            chat is InternalConversation
        }
        
        @MainActor
        public func isGroup() -> Bool {
            chat is GroupChat
        }
    }
    
    internal enum ContactListSorted: Comparable {
        case unRead, pinned, unPinRead
    }
    
    
    
    @MainActor
    public func arrangeBundle() async {
        for bundle in contactBundleViewModel {
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
        }
        
        var indexOfUnread = 0
        var lastUnread = 0
        
        for setBundle in contactBundleViewModel {
            guard let index = contactBundleViewModel.firstIndex(where: { $0.contact?.username == setBundle.contact?.username }) else { return }
            switch setBundle.sortedBy {
            case .unRead:
                movePosition(index: index, offset: indexOfUnread)
                indexOfUnread += 1
                lastUnread = indexOfUnread
            case .pinned:
                movePosition(index: index, offset: lastUnread + 1)
            case .unPinRead:
                movePosition(index: index, offset: contactBundleViewModel.count)
            }
        }
    }
    
    private func movePosition(index: Int, offset: Int) {
#if (os(macOS) || os(iOS))
        contactBundleViewModel.move(fromOffsets: IndexSet(integer: index), toOffset: offset)
#endif
    }
}

#if (os(macOS) || os(iOS))
extension ContactsBundle: ObservableObject {}
#endif
