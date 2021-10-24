import Foundation

public struct EncryptedObject: Codable {
    public var encryptedObjectString: String
    
    public init(encryptedObjectString: String) {
        self.encryptedObjectString = encryptedObjectString
    }
}
