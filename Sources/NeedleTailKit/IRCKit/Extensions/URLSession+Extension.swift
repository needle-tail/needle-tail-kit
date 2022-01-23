//
//  URLSession+Extension.swift
//  
//
//  Created by Cole M on 11/9/21.
//

import Foundation
import CypherMessaging
import CypherProtocol
import MessagingHelpers
import BSON

let maxBodySize = 500_000

// API
extension URLSession {
    
    func codableNetworkWrapper<T: Codable>(
        type: T.Type,
        httpHost: String,
        urlPath: String,
        httpMethod: String,
        httpBody: T? = nil,
        username: Username,
        deviceId: DeviceId,
        token: String? = nil
    ) async throws -> (Data, URLResponse) {
        
        var request = URLRequest(url: URL(string: "\(httpHost)/\(urlPath)")!)
        print(request.url as Any, "URL___")
        request.httpMethod = httpMethod
        request.addValue("application/bson", forHTTPHeaderField: "Content-Type")
        request.addValue(username.raw, forHTTPHeaderField: "X-API-User")
        request.addValue(deviceId.raw, forHTTPHeaderField: "X-API-Device")
        if let token = token {
            request.addValue(token, forHTTPHeaderField: "X-API-Token")
        }
        
        var decodedBSON: (Data, URLResponse)?
        do {
            
            if httpMethod == Network.post.rawValue || httpMethod == Network.put.rawValue {
                let data = try BSONEncoder().encode(httpBody).makeData()
                
                if data.count > maxBodySize {
                    return (Data(), URLResponse())
                }
                
                decodedBSON = try await self.upload(for: request, from: data)
                
                guard let httpResponse = decodedBSON?.1 as? HTTPURLResponse else {
                    throw IRCClientError.invalidResponse
                }
                guard httpResponse.statusCode == 200 else {
                    throw IRCClientError.invalidResponse
                }
                print("HTTPResponse_____", httpResponse)
                
            }
            
            if httpMethod == Network.get.rawValue {
                decodedBSON = try await self.data(for: request)
                
                guard let httpResponse = decodedBSON?.1 as? HTTPURLResponse else {
                    throw IRCClientError.invalidResponse
                }
                guard httpResponse.statusCode == 200 else {
                    throw IRCClientError.invalidResponse
                }
                print("HTTPResponse_____", httpResponse)
            }
        } catch {
            throw error
        }
        guard let decodedBSON = decodedBSON else {
            throw IRCClientError.nilBSONResponse
        }
        
        return decodedBSON
    }

}
