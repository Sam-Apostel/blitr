import AuthenticationServices
import PassKit
import PhotosUI
import SwiftUI

// The system buttons other frameworks put in SwiftUI screens, drawn in their published styles.

struct SystemButtons: View {
    @State private var photo: PhotosPickerItem?
    @State private var photos: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 14) {
            SignInWithAppleButton(.signIn, onRequest: { $0.requestedScopes = [.fullName, .email] }, onCompletion: { _ in })
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
            SignInWithAppleButton(.continue, onRequest: { _ in }, onCompletion: { _ in })
                .signInWithAppleButtonStyle(.whiteOutline)
                .frame(height: 50)
            SignInWithAppleButton(.signUp, onRequest: { _ in }, onCompletion: { _ in })
                .signInWithAppleButtonStyle(.white)
                .frame(height: 44)
            AddPassToWalletButton { }
                .frame(width: 260, height: 48)
            PayWithApplePayButton(.buy) { }
                .frame(height: 44)
            HStack {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose photo", systemImage: "photo.on.rectangle")
                }
                Spacer()
                PhotosPicker("Pick several", selection: $photos, maxSelectionCount: 5, matching: .images)
            }
        }
        .padding()
        .background(Color(white: 0.93))
    }
}

#Preview("System buttons") { SystemButtons() }
#Preview("System buttons, dark") { SystemButtons().preferredColorScheme(.dark) }
