import Foundation
import Logging
#if canImport(CryptoKit)
import CryptoKit
#else
import CommonCrypto
#endif

// Hashing data for logger
internal extension Logger.Metadata {
    
    ///  A static method used for hashing a string This is specifically helpful when trying to mask sensitive information in the ``Logger``.
    /// - Parameter string: A `String` intended for hashing
    /// - Returns: A hashed string
    static func hash(_ string: String) -> String? {
        var hashed: String = ""
#if canImport(CryptoKit)
        if #available(iOS 13.0, *) {
            hashed = SHA256.hash(data: Data(string.utf8)).compactMap { String(format: "%02x", $0) }.joined()
            return hashed
        }
#else
        if #available(iOS 10.0, *) {
            hashed = string.sha256()
        }
#endif
        return hashed
    }
}

// Hashing Pre iOS 13
internal extension String {
    
    /// If we are not using **iOS >= 13** then we cannot use `CryptoKit`. We implement the same hashing using `CommonCrypto`
    /// - Returns: A hashed string
    func sha256() -> String{
        if let stringData = self.data(using: String.Encoding.utf8) {
            return stringData.sha256()
        }
        return ""
    }
}


internal extension String {
    
    /// A method used to return a string that contains a range of characters
    /// - Parameter length: An integer value to span over
    /// - Returns: An array containing the desire range
    func components(withMaxLength length: Int) -> [String] {
        return stride(from: 0, to: self.count, by: length).map {
            let start = self.index(self.startIndex, offsetBy: $0)
            let end = self.index(start, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
            return String(self[start..<end])
        }
    }
}
