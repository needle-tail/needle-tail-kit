//
//  Network.swift
//
//
//  Created by Cole M on 11/7/21.
//


public enum Network: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

public enum HeaderFields: String {
    case authorization = "Authorization"
    case contentType = "Content-Type"
    case connection = "Connection"
    case date = "Date"
    case application = "Application"
    case contentSecurityPolicy = "content-security-policy"
    case xXSSProtection = "x-xss-protection"
    case xContentTypeOptions = "x-content-type-options"
    case userAgent = "User-Agent"
    case xFrameOptions = "x-frame-options"
}

public enum HeaderValues: String {
    case bearerAuth = "Bearer "
    case basicAuth = "Basic "
    case applicationJson = "application/json"
    case applicationBson = "application/bson"
    case cartisimApp = "CartisimApp"
    case keepAlive = "keep-alive"
    case cartisim = "Cartisim"
    case defaultSCR = "default-src 'none'"
    case noSniff = "nosniff"
    case deny = "DENY"
    case xXSSProtectionValue = "1; mode=block"
}
