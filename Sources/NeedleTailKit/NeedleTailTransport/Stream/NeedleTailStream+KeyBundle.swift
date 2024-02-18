//
//  NeedleTailStream+Registration.swift
//  
//
//  Created by Cole M on 1/15/24.
//

import CypherMessaging
import NeedleTailProtocol

extension NeedleTailStream {
    
    func updateKeyBundle() async {
        //set this to true in order to tell publishKeyBundle that we are adding a device
        updateKeyBundle = true
    }

    public func doReadKeyBundle(_ keyBundle: [String]) async throws {
        guard let keyBundle = keyBundle.first else { throw KeyBundleErrors.cannotReadKeyBundle }
        guard let data = Data(base64Encoded: keyBundle) else { throw KeyBundleErrors.cannotReadKeyBundle }
        let config = try BSONDecoder().decodeData(UserConfig.self, from: data)
        await configuration.store.setKeyBundle(config)
    }
    
    /// Request from the server a users key bundle
    /// - Parameter packet: Our Authentication Packet
    func readKeyBundle(_ packet: String) async throws {
        try await configuration.writer.transportMessage(command: .otherCommand(Constants.readKeyBundle.rawValue, [packet]))
    }
    
    enum KeyBundleErrors: Error {
        case cannotReadKeyBundle, nilData
    }
    
}
