import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif

extension Data{
    
    /// Creates sha256 string from Data
    /// - Returns: SHA256 Hash
    internal func sha256() -> String {
        return hexStringFromData(input: digest(input: self as NSData))
    }
    
    /// Digest Data as an input on the `Data` Type
    /// - Parameter input: `NSData`
    /// - Returns: return the digested data as `NSData`
    private func digest(input : NSData) -> NSData {
        let digestLength = Int(CC_SHA256_DIGEST_LENGTH)
        var hash = [UInt8](repeating: 0, count: digestLength)
        CC_SHA256(input.bytes, UInt32(input.length), &hash)
        return NSData(bytes: hash, length: digestLength)
    }
    
    /// Creates a Hex String from our Digested `NSData`
    /// - Parameter input: `NSData`
    /// - Returns: A hexString from the `Digest` of `NSData`
    private func hexStringFromData(input: NSData) -> String {
        var bytes = [UInt8](repeating: 0, count: input.length)
        input.getBytes(&bytes, length: input.length)
        
        var hexString = ""
        for byte in bytes {
            hexString += String(format:"%02x", UInt8(byte))
        }
        return hexString
    }
}
