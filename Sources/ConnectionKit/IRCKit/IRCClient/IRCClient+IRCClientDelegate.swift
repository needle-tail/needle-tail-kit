//
//  File.swift
//  
//
//  Created by Cole M on 9/19/21.
//

import Foundation
import NIOIRC


extension IRCClient: IRCClientDelegate {
    
    // MARK: - Messages
    
    public func client(_       client : IRCNIOHandler,
                       notice message : String,
                       for recipients : [ IRCMessageRecipient ])
    {
        Q.async {
            self.updateConnectedClientState(client)
            
            // FIXME: this is not quite right, mirror what we do in message
            self.conversationsForRecipients(recipients).forEach {
                $0.addNotice(message)
            }
        }
    }
    public func client(_       client : IRCNIOHandler,
                       message        : String,
                       from    sender : IRCUserID,
                       for recipients : [ IRCMessageRecipient ])
    {
        Q.async {
            self.updateConnectedClientState(client)
            
            // FIXME: We need this because for DMs we use the sender as the
            //        name
            for recipient in recipients {
                switch recipient {
                case .channel(let name):
                    if let c = self.registerChannel(name.stringValue) {
                        c.addMessage(message, from: sender)
                    }
                case .nickname: // name should be us
                    if let c = self.registerDirectMessage(sender.nick.stringValue) {
                        c.addMessage(message, from: sender)
                    }
                case .everything:
                    self.conversations.values.forEach {
                        $0.addMessage(message, from: sender)
                    }
                }
            }
        }
    }
    
    public func client(_ client: IRCNIOHandler, messageOfTheDay message: String) {
        Q.async {
            self.updateConnectedClientState(client)
            self.messageOfTheDay = message
        }
    }
    
    
    // MARK: - Channels
    
    public func client(_ client: IRCNIOHandler,
                       user: IRCUserID, joined channels: [ IRCChannelName ])
    {
        Q.async {
            self.updateConnectedClientState(client)
            channels.forEach { self.registerChannel($0.stringValue) }
        }
    }
    public func client(_ client: IRCNIOHandler,
                       user: IRCUserID, left channels: [ IRCChannelName ],
                       with message: String?)
    {
        Q.async {
            self.updateConnectedClientState(client)
            channels.forEach { self.unregisterChannel($0.stringValue) }
        }
    }
    
    public func client(_ client: IRCNIOHandler,
                       changeTopic welcome: String, of channel: IRCChannelName)
    {
        Q.async {
            self.updateConnectedClientState(client)
            // TODO: operation
        }
    }
    
    
    // MARK: - Connection
    
    /**
     * Bring the service online if necessary, update derived properties.
     * This is called by all methods that signal connectivity.
     */
    private func updateConnectedClientState(_ client: IRCNIOHandler) {
        switch self.state {
        case .offline, .suspended:
            assertionFailure("not connecting, still getting connected client info")
            return
            
        case .connecting(let ownClient):
            guard client === ownClient else {
                assertionFailure("client mismatch")
                return
            }
            print("going online:", client)
            self.state = .online(client)
            
            let channels = account.joinedChannels.compactMap(IRCChannelName.init)
            
            // TBD: looks weird. doJoin is for replies?
            client.sendMessage(.init(command: .JOIN(channels: channels, keys: nil)))
            
        case .online(let ownClient):
            guard client === ownClient else {
                assertionFailure("client mismatch")
                return
            }
        // TODO: update state (nick, userinfo, etc)
        }
    }
    
    public func client(_ client        : IRCNIOHandler,
                       registered nick : IRCNickName,
                       with   userInfo : IRCUserInfo) {
        Q.async { self.updateConnectedClientState(client) }
    }
    public func client(_ client: IRCNIOHandler, changedNickTo nick: IRCNickName) {
        Q.async { self.updateConnectedClientState(client) }
    }
    public func client(_ client: IRCNIOHandler, changedUserModeTo mode: IRCUserMode) {
        Q.async { self.updateConnectedClientState(client) }
    }
    
    public func clientFailedToRegister(_ newClient: IRCNIOHandler) {
        Q.async {
            switch self.state {
            case .offline, .suspended:
                assertionFailure("not connecting, still get registration failure")
                return
                
            case .connecting(let ownClient), .online(let ownClient):
                guard newClient === ownClient else {
                    assertionFailure("client mismatch")
                    return
                }
                
                print("Closing client ...")
                ownClient.delegate = nil
                self.state = .offline
                ownClient.disconnect()
            }
        }
    }
}
