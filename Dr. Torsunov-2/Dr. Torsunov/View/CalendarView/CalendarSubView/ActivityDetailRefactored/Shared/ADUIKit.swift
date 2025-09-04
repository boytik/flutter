import SwiftUI

// Local, namespaced helper to avoid collisions with app-level symbols.
struct ADFixedRemoteImage: View {
    let url: URL?
    var aspect: CGFloat = 3.0/4.0
    var corner: CGFloat = 12

    init(url: URL?, aspect: CGFloat = 3.0/4.0, corner: CGFloat = 12) {
        self.url = url; self.aspect = aspect; self.corner = corner
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url, transaction: .init(animation: .easeInOut)) { phase in
                    switch phase {
                    case .empty: ProgressView().tint(.white)
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: placeholder
                    @unknown default: placeholder
                    }
                }
            } else { placeholder }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspect, contentMode: .fill)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.white.opacity(0.06))
            Image(systemName: "photo").font(.system(size: 22, weight: .semibold)).foregroundColor(.white.opacity(0.6))
        }
        .aspectRatio(aspect, contentMode: .fit)
    }
}

@ViewBuilder
func adSectionTitle(_ text: String) -> some View {
    Text(text).font(.headline).foregroundColor(.white)
}
