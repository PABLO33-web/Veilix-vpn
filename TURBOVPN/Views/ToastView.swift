import SwiftUI

struct ToastView: View {
    let message: String
    @Binding var isShowing: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.white)
                .font(.system(size: 20))
            
            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.95))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 10)
    }
} 