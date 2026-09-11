//
//  PTYMOBDFirmwareCrypto.swift
//  CrazyDashboard
//
//  EN: Implements the documented YMOBD firmware envelope without starting OTA.
//  ES: Implementa el sobre de firmware YMOBD documentado sin iniciar OTA.
//  中文：实现文档中的 YMOBD 固件加密封装，但不会启动 OTA。
//

import CommonCrypto
import CryptoKit
import Foundation
import Security

public struct PTYMOBDFirmwareSecret: Codable, Equatable, Sendable {
    public let keyString: String
    public let encryptKey: String
    public let publicKeyVersion: Int

    public init(keyString: String, encryptKey: String, publicKeyVersion: Int) {
        self.keyString = keyString
        self.encryptKey = encryptKey
        self.publicKeyVersion = publicKeyVersion
    }
}

public enum PTYMOBDFirmwareCryptoError: Error, Equatable, LocalizedError, Sendable {
    case invalidKeyString
    case invalidPublicKey
    case rsaEncryptionFailed
    case emptyEncryptedFirmware
    case aesInitializationFailed(status: Int32)
    case aesDecryptionFailed(status: Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidKeyString:
            return "固件密钥长度无效"
        case .invalidPublicKey:
            return "YMOBD 固件公钥无效"
        case .rsaEncryptionFailed:
            return "固件密钥 RSA 加密失败"
        case .emptyEncryptedFirmware:
            return "下载的加密固件为空"
        case let .aesInitializationFailed(status):
            return "AES-OFB 初始化失败（\(status)）"
        case let .aesDecryptionFailed(status):
            return "AES-OFB 解密失败（\(status)）"
        }
    }
}

public enum PTYMOBDFirmwareCrypto {
    public static let publicKeyVersion = 3
    public static let publicKeyFingerprint = "aba7ea13c8829866703aa87f63b29649eb28c0d4be348383cb458e883598fae1"

    // EN: This is the documented RSA-2048 SubjectPublicKeyInfo, kept public-key-only by design.
    // ES: Esta es la clave pública SubjectPublicKeyInfo RSA-2048 documentada; por diseño solo contiene la parte pública.
    // 中文：这是文档确认的 RSA-2048 SubjectPublicKeyInfo，只保留公钥部分。
    private static let publicKeyPEM = """
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtYT8O4diulE8FDFC89Dq
    bevMrppsCm8JT5KHMkYNqmEnoajch9NjUAEXFG6nEOKG4jngQ6oMuPNLiJEEKI5m
    tzUMImpAP/g0sCBUDnrB7r8CovULM9KY7KG2J4vgopX2EbKOfhLeUcDA/hD0+iPN
    IyaYMmBdnYsrpXQ5NZHR0dVpDquwnRVrZGr6XIxheoWWC1hfA4/0pAiZpWdqQljC
    mDolX6clSXW2RKZyEu7jZ24xY53ntxPP0S9TDivvxNJ5GYvGLqUm/j3Tejz0I9qg
    lCQrx47U6nwhRcD86gW6PZU57x08w5yH+s1cCIIO9yKIB86Hu7UoW69zbtJTQANW
    2QIDAQAB
    -----END PUBLIC KEY-----
    """

    // EN: Create the per-download UUID key and wrap its 32 ASCII bytes with RSA PKCS#1 v1.5.
    // ES: Crea la clave UUID por descarga y envuelve sus 32 bytes ASCII con RSA PKCS#1 v1.5.
    // 中文：为每次下载生成 UUID 密钥，并使用 RSA PKCS#1 v1.5 加密其 32 个 ASCII 字节。
    public static func createSecret() throws -> PTYMOBDFirmwareSecret {
        let keyString = UUID().uuidString.lowercased()
        let aesKey = try aesKeyData(from: keyString)
        let publicKey = try makePublicKey()

        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionPKCS1,
            aesKey as CFData,
            &error
        ) as Data? else {
            throw PTYMOBDFirmwareCryptoError.rsaEncryptionFailed
        }

        return PTYMOBDFirmwareSecret(
            keyString: keyString,
            encryptKey: hexString(encrypted),
            publicKeyVersion: publicKeyVersion
        )
    }

    // EN: OFB is a stream mode, so CommonCrypto decrypts it with the same zero IV and key shape documented by YMOBD.
    // ES: OFB es un modo de flujo; CommonCrypto lo descifra con el mismo IV cero y la forma de clave documentada por YMOBD.
    // 中文：OFB 属于流模式，CommonCrypto 使用文档规定的全零 IV 和相同密钥形态进行解密。
    public static func decryptFirmware(encryptedData: Data, keyString: String) throws -> Data {
        guard !encryptedData.isEmpty else {
            throw PTYMOBDFirmwareCryptoError.emptyEncryptedFirmware
        }

        let keyData = try aesKeyData(from: keyString)
        let iv = Data(repeating: 0, count: kCCBlockSizeAES128)
        var cryptor: CCCryptorRef?
        let createStatus = keyData.withUnsafeBytes { keyBuffer in
            iv.withUnsafeBytes { ivBuffer in
                CCCryptorCreateWithMode(
                    CCOperation(kCCDecrypt),
                    CCMode(kCCModeOFB),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivBuffer.baseAddress,
                    keyBuffer.baseAddress,
                    keyData.count,
                    nil,
                    0,
                    0,
                    0,
                    &cryptor
                )
            }
        }

        guard createStatus == kCCSuccess, let cryptor else {
            throw PTYMOBDFirmwareCryptoError.aesInitializationFailed(status: Int32(createStatus))
        }
        defer { CCCryptorRelease(cryptor) }

        var output = Data(count: encryptedData.count)
        var movedBytes = 0
        let updateStatus = encryptedData.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                CCCryptorUpdate(
                    cryptor,
                    inputBuffer.baseAddress,
                    encryptedData.count,
                    outputBuffer.baseAddress,
                    outputBuffer.count,
                    &movedBytes
                )
            }
        }
        guard updateStatus == kCCSuccess else {
            throw PTYMOBDFirmwareCryptoError.aesDecryptionFailed(status: Int32(updateStatus))
        }

        var finalBuffer = Data(count: kCCBlockSizeAES128)
        var finalBytes = 0
        let finalStatus = finalBuffer.withUnsafeMutableBytes { buffer in
            CCCryptorFinal(cryptor, buffer.baseAddress, buffer.count, &finalBytes)
        }
        guard finalStatus == kCCSuccess else {
            throw PTYMOBDFirmwareCryptoError.aesDecryptionFailed(status: Int32(finalStatus))
        }

        var result = Data(output.prefix(movedBytes))
        result.append(finalBuffer.prefix(finalBytes))
        guard !result.isEmpty else {
            throw PTYMOBDFirmwareCryptoError.emptyEncryptedFirmware
        }
        return result
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension PTYMOBDFirmwareCrypto {
    static func aesKeyData(from keyString: String) throws -> Data {
        let compact = keyString.replacingOccurrences(of: "-", with: "")
        guard compact.utf8.count == kCCKeySizeAES256,
              let data = compact.data(using: .utf8),
              data.count == kCCKeySizeAES256 else {
            throw PTYMOBDFirmwareCryptoError.invalidKeyString
        }
        return data
    }

    static func makePublicKey() throws -> SecKey {
        let subjectPublicKeyInfo = try publicKeyDER()
        let fingerprint = sha256Hex(subjectPublicKeyInfo)
        guard fingerprint == publicKeyFingerprint else {
            throw PTYMOBDFirmwareCryptoError.invalidPublicKey
        }

        let candidates = [subjectPublicKeyInfo, pkcs1PublicKey(from: subjectPublicKeyInfo)].compactMap { $0 }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 2048
        ]

        for candidate in candidates {
            var error: Unmanaged<CFError>?
            guard let key = SecKeyCreateWithData(
                candidate as CFData,
                attributes as CFDictionary,
                &error
            ) else {
                continue
            }

            guard SecKeyGetBlockSize(key) == 256,
                  SecKeyIsAlgorithmSupported(key, .encrypt, .rsaEncryptionPKCS1) else {
                continue
            }
            return key
        }

        throw PTYMOBDFirmwareCryptoError.invalidPublicKey
    }

    static func publicKeyDER() throws -> Data {
        let base64 = publicKeyPEM
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else {
            throw PTYMOBDFirmwareCryptoError.invalidPublicKey
        }
        return data
    }

    static func pkcs1PublicKey(from subjectPublicKeyInfo: Data) -> Data? {
        var rootOffset = 0
        guard let root = readDERElement(from: subjectPublicKeyInfo, offset: &rootOffset), root.tag == 0x30 else {
            return nil
        }

        var bodyOffset = 0
        guard readDERElement(from: root.value, offset: &bodyOffset) != nil,
              let bitString = readDERElement(from: root.value, offset: &bodyOffset),
              bitString.tag == 0x03,
              bitString.value.first == 0 else {
            return nil
        }
        return Data(bitString.value.dropFirst())
    }

    static func readDERElement(from data: Data, offset: inout Int) -> (tag: UInt8, value: Data)? {
        guard offset < data.count else { return nil }
        let tag = data[offset]
        offset += 1

        guard offset < data.count else { return nil }
        let lengthByte = data[offset]
        offset += 1

        let length: Int
        if lengthByte & 0x80 == 0 {
            length = Int(lengthByte)
        } else {
            let byteCount = Int(lengthByte & 0x7F)
            guard byteCount > 0, byteCount <= 4, offset + byteCount <= data.count else { return nil }
            var parsedLength = 0
            for _ in 0..<byteCount {
                parsedLength = (parsedLength << 8) | Int(data[offset])
                offset += 1
            }
            length = parsedLength
        }

        guard length >= 0, offset + length <= data.count else { return nil }
        let value = data[offset..<(offset + length)]
        offset += length
        return (tag, Data(value))
    }

    static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}
