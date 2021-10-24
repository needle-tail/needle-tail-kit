//
//  ChatHandler.swift
//  Cartisim
//
//  Created by Cole M on 3/9/21.
//  Copyright © 2021 Cole M. All rights reserved.
//

import NIO
import Foundation

public typealias EncryptedServerDataReceived = (EncryptedObject) -> ()
public typealias ServerDataReceived = (MessageData) -> ()

public final class JSONDecoderHandler<Message: Decodable>: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = Message
    public var isEncryptedObject: Bool
    public let jsonDecoder: JSONDecoder
    
    public init(isEncryptedObject: Bool, jsonDecoder: JSONDecoder = JSONDecoder()) {
        self.isEncryptedObject = isEncryptedObject
        self.jsonDecoder = jsonDecoder
    }
    
    
    public var dataReceived: ServerDataReceived?
    public var encryptedDataReceived: EncryptedServerDataReceived?
    
    private enum ServerResponse {
        case dataFromServer
        case error(Error)
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        print("Chat Client connected to \(context.remoteAddress!)")
        context.fireChannelActive()
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        let channel = context.channel
        print(channel, "INACTIVE")
        context.fireChannelInactive()
    }
    
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Error Caught: ", error)
        context.close(promise: nil)
    }
    
    private var currentlyWaitingFor = ServerResponse.dataFromServer {
        didSet {
            if case .error(let error) = self.currentlyWaitingFor {
                print(error, "Waiting for errror")
            }
        }
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny){
        switch self.currentlyWaitingFor {
        case .dataFromServer:
            let bytes = self.unwrapInboundIn(data)
            
            if isEncryptedObject == true {
                guard let receivedEncryptedData = encryptedDataReceived else {return}
                guard let decodeEncryptedData = try? self.jsonDecoder.decode(Message.self, from: bytes) as? EncryptedObject else {return}
                receivedEncryptedData(EncryptedObject(encryptedObjectString: decodeEncryptedData.encryptedObjectString))
            } else {
                guard let receivedData = dataReceived else {return}
                guard let decodeData = try? self.jsonDecoder.decode(Message.self, from: bytes) as? MessageData else {return}
                receivedData(MessageData(avatar: decodeData.avatar, userID: decodeData.userID, name: decodeData.name, message: decodeData.message, accessToken: decodeData.accessToken, refreshToken: decodeData.refreshToken, sessionID: decodeData.sessionID, chatSessionID: decodeData.chatSessionID))
            }
            
        case .error(let error):
            fatalError("We have a fatal receiving data from the server: \(error)")
        }
    }
}
