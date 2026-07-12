//
//  UserProfileManager.swift
//  ZhenHaoXuan
//
//  用户资料管理器 - 处理Apple账户头像和用户信息
//
//  安全策略：用户名、头像等个人信息存 Keychain（加密保险柜），
//  不再明文存 UserDefaults。
//

import Foundation
import SwiftUI
import Combine
import AuthenticationServices

@MainActor
final class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()

    // MARK: - Published Properties
    @Published var userName: String = "用户"
    @Published var userImage: UIImage?
    @Published var isSignedIn: Bool = false

    // MARK: - Keychain Keys（个人信息放加密保险柜）
    private enum KeychainKey {
        static let userName = "userProfileName"
        static let userImageData = "userProfileImageData"
        static let isSignedIn = "userProfileIsSignedIn"
    }

    // MARK: - Initialization
    private init() {
        loadUserProfile()
    }

    // MARK: - User Profile Management

    private func loadUserProfile() {
        userName = (try? KeychainManager.readString(key: KeychainKey.userName)) ?? "用户"
        isSignedIn = KeychainManager.readBool(key: KeychainKey.isSignedIn)

        if let imageData = KeychainManager.readData(key: KeychainKey.userImageData),
           let image = UIImage(data: imageData) {
            userImage = image
        } else {
            userImage = nil
        }
    }

    func saveUserProfile(name: String, image: UIImage?) {
        userName = name
        try? KeychainManager.writeString(key: KeychainKey.userName, value: name)

        if let image = image, let imageData = image.jpegData(compressionQuality: 0.8) {
            userImage = image
            try? KeychainManager.write(key: KeychainKey.userImageData, data: imageData)
        } else {
            userImage = nil
            try? KeychainManager.delete(key: KeychainKey.userImageData)
        }

        isSignedIn = true
        KeychainManager.writeBool(key: KeychainKey.isSignedIn, value: true)
    }

    func clearUserProfile() {
        userName = "用户"
        userImage = nil
        isSignedIn = false

        KeychainManager.clearAll()
    }

    // MARK: - Apple Sign In

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                let components = [
                    appleIDCredential.fullName?.familyName,
                    appleIDCredential.fullName?.givenName
                ]
                let suppliedName = components
                    .compactMap { $0 }
                    .joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let name = suppliedName.isEmpty ? (isSignedIn ? userName : "Apple用户") : suppliedName
                let defaultImage = createDefaultAvatar(name: name)
                saveUserProfile(name: name, image: defaultImage)
            }

        case .failure(let error):
            print("Apple Sign In failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Default Avatar

    func createDefaultAvatar(name: String) -> UIImage {
        let size = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)

        let initial = String(name.prefix(1)).uppercased()

        let image = renderer.image { context in
            let gradientColors = [
                UIColor.systemBlue.cgColor,
                UIColor.systemPurple.cgColor
            ]

            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: gradientColors as CFArray,
                locations: [0, 1]
            )!

            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 80, weight: .medium),
                .foregroundColor: UIColor.white
            ]

            let textSize = initial.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )

            initial.draw(in: textRect, withAttributes: attributes)
        }

        return image
    }
}
