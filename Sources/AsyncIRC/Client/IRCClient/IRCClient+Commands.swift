//
//  IRCClient+Commands.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIO

extension IRCClient {
    
    public func sendMessage(_ message: IRCMessage, chatDoc: ChatDocument?) async {
        do {
            try await channel?.writeAndFlush(message)
        } catch {
            print(error)
        }
    }
    
    // MARK: - Commands
    internal func _register(_ regPacket: String?) async {
        guard case .registering(_, let nick, let user) = state else {
            assertionFailure("called \(#function) but we are not connecting?")
            return
        }
        
        if let pwd = options.password {
            await send(.otherCommand("PASS", [ pwd ]))
        }
        
        if let regPacket = regPacket {
            let tag = IRCTags(key: "registrationPacket", value: regPacket)
            await send(.NICK(nick), tags: [tag])
        } else {
            await send(.NICK(nick))
        }
        await send(.USER(user))
    }
    
    
    public func publishKeyBundle(_ keyBundle: String) async {
        await send(.otherCommand("PUBKEYBNDL", [keyBundle]))
    }
    
    
    public func readKeyBundle(_ packet: String) async {
        await send(.otherCommand("READKEYBNDL", [packet]))
    }
    
    public func acknowledgeMessageReceived(_ acknowledge: String) async {
        await send(.otherCommand("ACKMESSAGE", [acknowledge]))
    }
    
    public func registerAPN(_ packet: String) async {
        await send(.otherCommand("REGAPN", [packet]))
    }
    
    public func changeNick(_ nick: IRCNickName) async {
        await send(.NICK(nick))
    }
    
    internal func _resubscribe() {
        if !subscribedChannels.isEmpty {
            // TODO: issues JOIN commands
        }
    }
    
    internal func _closeOnUnexpectedError(_ error: Swift.Error? = nil) {
        assert(eventLoop.inEventLoop, "threading issue")
        
        if let error = error {
            self.retryInfo.lastSocketError = error
        }
    }
    
    
    internal func close() async {
        do {
            _ = try await channel?.close(mode: .all)
            try await self.groupManager.syncShutdown()
            messageOfTheDay = ""
        } catch {
            print("Could not gracefully shutdown, Forcing the exit (\(error)")
            exit(0)
        }
        print("closed server")
    }
    
    
    func handleRegistrationDone() async {
        guard case .registering(let channel, let nick, let user) = state else {
            assertionFailure("called \(#function) but we are not registering?")
            return
        }
        
        state = .registered(channel: channel, nick: nick, userInfo: user)
        await delegate?.client(self, registered: nick, with: user)
        
        self._resubscribe()
    }
    
    
    func handleRegistrationFailed(with message: IRCMessage) async {
        guard case .registering(_, let nick, _) = state else {
            assertionFailure("called \(#function) but we are not registering?")
            return
        }
        // TODO: send to delegate
        print("ERROR: registration of \(nick) failed:", message)
        
        await delegate?.clientFailedToRegister(self)
        _closeOnUnexpectedError()
    }
    
    
    // This is where we receive all messages from server in the client
    
    func handlerHandleResult(_ message: IRCMessage) async {
        if case .registering = state {
            if message.command.signalsSuccessfulRegistration {
                await handleRegistrationDone()
            }
            
            if case .numeric(.errorNicknameInUse, _) = message.command {
                return await handleRegistrationFailed(with: message)
            }
            else if message.command.isErrorReply {
                return await handleRegistrationFailed(with: message)
            }
        }
        
        do {
            try await irc_msgSend(message)
        }
        catch let error as IRCDispatcherError {
            // TBD:
            print("handle dispatcher error:", error)
        }
        catch {
            // TBD:
            print("handle generic error:", type(of: error), error)
        }
        
    }
    
}
