//
//  IRCClient+Commands.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIO
import NeedleTailHelpers

extension IRCClient {
    
    
    internal func _closeOnUnexpectedError(_ error: Swift.Error? = nil) {
        assert(eventLoop.inEventLoop, "threading issue")
        
        if let error = error {
            self.retryInfo.lastSocketError = error
        }
    }
    
    @NeedleTailActor
    func shutdownClient() async {
        do {
            _ = try await channel?.close(mode: .all)
            try await self.groupManager.shutdown()
            messageOfTheDay = ""
        } catch {
            print("Could not gracefully shutdown, Forcing the exit (\(error)")
            exit(0)
        }
        logger.info("disconnected from server")
    }
    
    
    func handleRegistrationDone() async {
        guard case .registering(let channel, let nick, let user) = userState.state else {
//            assertionFailure("called \(#function) but we are not registering?")
            return
        }
        
        userState.transition(to: .registered(channel: channel, nick: nick, userInfo: user))
        await delegate?.client(self, registered: nick, with: user)
        
        //TODO: JOIN CHANNELS in resubscribe
        self._resubscribe()
    }
    
    
    func handleRegistrationFailed(with message: IRCMessage) async {
        guard case .registering(_, let nick, _) = userState.state else {
            assertionFailure("called \(#function) but we are not registering?")
            return
        }
        // TODO: send to delegate
        print("ERROR: registration of \(nick) failed:", message)
        
        await delegate?.clientFailedToRegister(self)
        _closeOnUnexpectedError()
    }
}
