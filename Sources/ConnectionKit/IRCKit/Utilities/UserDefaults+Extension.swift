//
//  File.swift
//  
//
//  Created by Cole M on 9/19/21.
//

import Foundation

public enum UserDefaultKeys: String {
    
    // MARK: - Navigation
    case lastAccountID
    case lastConversationID
    
    // MARK: - Accounts Database
    case accounts
}

extension UserDefaults {
    
    func set(_ value: String, forKey key: UserDefaultKeys) {
        set(value, forKey: key.rawValue)
    }
    func set(_ value: String?, forKey key: UserDefaultKeys) {
        set(value, forKey: key.rawValue)
    }
    
    func string(forKey key: UserDefaultKeys) -> String? {
        return string(forKey: key.rawValue)
    }
}

extension UserDefaults {
    
    public func decode<T: Decodable>(_ type: T.Type, forKey key: UserDefaultKeys) throws
    -> T?
    {
        let jsonData : Data = data(forKey: key.rawValue) ?? {
            guard let plist = value(forKey: key.rawValue) else { return nil }
            return try? JSONSerialization.data(withJSONObject: plist, options: [])
        }() ?? Data()
        
        return try JSONDecoder().decode(type, from: jsonData)
    }
    
    public func encode<T: Encodable>(_ object: T, forKey key: UserDefaultKeys) throws {
        let jsonData = try JSONEncoder().encode(object)
        let plist = try JSONSerialization.jsonObject(with: jsonData, options: [])
        setValue(plist, forKey: key.rawValue)
    }
}
