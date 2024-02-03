import NeedleTailCrypto
import CypherMessaging
import Crypto
import SwiftDTF

extension NeedleTailCrypto {
    
    public func encryptCodableCypherObject<T: Codable>(_ object: T, cypher: CypherMessenger) throws -> Data? {
        let userData = try BSONEncoder().encodeData(object)
        let file = try cypher.encryptLocalFile(userData)
        return file.combined
    }
    
    public func decryptCypherObject<T: Codable>(blob: Data, cypher: CypherMessenger) throws -> T? {
        let data = try cypher.decryptLocalFile(AES.GCM.SealedBox(combined: blob))
        return try BSONDecoder().decodeData(T.self, from: data)
    }
    
    public func encryptCodableObject<T: Codable>(_ object: T, usingKey key: SymmetricKey) throws -> Data? {
        let userData = try BSONEncoder().encodeData(object)
        let encryptedData = try AES.GCM.seal(userData, using: key)
        return encryptedData.combined
    }
    
    public func decryptStringToCodableObject<T: Codable>(_ type: T.Type, from string: String, usingKey key: SymmetricKey) throws -> T {
        let data = Data(base64Encoded: string)!
        let box = try AES.GCM.SealedBox(combined: data)
        let decryptData = try AES.GCM.open(box, using: key)
        return try BSONDecoder().decodeData(type, from: decryptData)
    }
}

extension NeedleTailCrypto {
    private func createData(message: SingleCypherMessage, cypher: CypherMessenger) async throws -> Data {
        guard let filePath = message.metadata["filePath"] as? String else { throw NeedleTailError.filePathDoesntExist }
        guard let blob = try DataToFile.shared.generateData(from: filePath) else { throw NeedleTailError.nilData }
        let fileComponents = filePath.components(separatedBy: ".")
        guard let name = fileComponents.first else { fatalError("File Name Does Not Exist") }
        guard let type = fileComponents.last else { fatalError("File Type Does Not Exist") }
        try DataToFile.shared.removeItem(fileName: name, fileType: type)
        //Decrypt
        return try cypher.decryptLocalFile(AES.GCM.SealedBox(combined: blob))
    }
    
    public func decryptFileData(_ fileData: Data, cypher: CypherMessenger) async throws -> Data {
        guard let fileName = String(data: fileData, encoding: .utf8) else { throw NeedleTailError.nilData }
        guard let blob = try DataToFile.shared.generateData(from: fileName) else { throw NeedleTailError.nilData }
        let fileComponents = fileName.components(separatedBy: ".")
        guard let name = fileComponents.first else { fatalError("File Name Does Not Exist") }
        guard let type = fileComponents.last else { fatalError("File Type Does Not Exist") }
        try DataToFile.shared.removeItem(fileName: name, fileType: type)
        let data = try cypher.decryptLocalFile(AES.GCM.SealedBox(combined: blob))
        return data
    }
    
    public func decryptFile(from path: String, cypher: CypherMessenger, shouldRemove: Bool = false) async throws -> Data {
        var path = path
        do {
            guard let blob = try DataToFile.shared.generateData(from: path) else { throw NeedleTailError.nilData }
            if path.contains("/") {
                path = path.components(separatedBy: "/").last ?? ""
            }
            
            if shouldRemove {
                guard let name = path.components(separatedBy: ".").first else { fatalError() }
                guard let fileType = path.components(separatedBy: ".").last else { fatalError() }
                try DataToFile.shared.removeItem(fileName: name, fileType: fileType)
            }
            let data = try cypher.decryptLocalFile(AES.GCM.SealedBox(combined: blob))
            return data
        } catch let error as DataToFile.Errors {

            // rebuild name
            if error == .fileComponenteTooSmall {
                //Update Path
                if path.contains("/") {
                    path = path.components(separatedBy: "/").last ?? ""
                }
                
                let fm = FileManager.default
                let paths = fm.urls(for: .documentDirectory, in: .userDomainMask)
                guard let documentsDirectory = paths.first else { fatalError("Directory does not exist") }
                let saveDirectory = documentsDirectory.appendingPathComponent("Media")
                let fileURL = saveDirectory.appendingPathComponent(path)
                let fileData = try Data(contentsOf: fileURL, options: .alwaysMapped)
                if !path.contains(".") {
                    path = path + ".jpg"
                }
                guard let name = path.components(separatedBy: ".").first else { fatalError() }
                guard let fileType = path.components(separatedBy: ".").last else { fatalError() }
                let fileLocation = try DataToFile.shared.generateFile(
                    data: fileData,
                    fileName: "\(name)_\(cypher.deviceId.raw)",
                    fileType: fileType
                )

                if fileURL.relativePath.contains(".") {
                    try DataToFile.shared.removeItem(fileName: name, fileType: fileType)
                } else {
                    try DataToFile.shared.removeItem(fileName: name, fileType: "")
                }
                guard let newBlob = try DataToFile.shared.generateData(from: fileLocation) else { throw NeedleTailError.nilData }
                return newBlob
            }
           fatalError()
        }
    }
}
