import SwiftUI

/// Две фотографии рядом (До/После) с ЖЁСТКОЙ рамкой:
/// - фиксируем высоту карточки исходя из ширины и aspectRatio (по умолчанию 3:4);
/// - изображение всегда .scaledToFill() + .clipped() внутри рамки;
/// - наружная высота задана явно -> ничего не наедет на элементы ниже.
struct PhotoCompareGrid: View {
    let beforeURL: URL?
    let afterURL: URL?

    /// Ширина : высота; для портрета удобно 3:4 (0.75)
    var aspectWH: CGFloat = 3.0 / 4.0
    var cornerRadius: CGFloat = 18
    var spacing: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            // ширина каждой карточки
            let tileW = floor((geo.size.width - spacing) / 2.0)
            // высота по портретному соотношению:  H = W / (W:H)
            let tileH = max(160, tileW / aspectWH)

            HStack(spacing: spacing) {
                PhotoTile(url: beforeURL, width: tileW, height: tileH, cornerRadius: cornerRadius)
                PhotoTile(url: afterURL,  width: tileW, height: tileH, cornerRadius: cornerRadius)
            }
            .frame(width: geo.size.width, height: tileH)
        }
        // наружная высота — фиксируем, чтобы грид корректно резервировал место в раскладке
        .frame(height:  // та же формула, но с приблизительной шириной экрана
            UIScreen.main.bounds.width > 0
            ? max(160, ((UIScreen.main.bounds.width - 32 - spacing) / 2.0) / aspectWH)
            : 220
        )
        .padding(.bottom, 12)      // зазор до пикеров/текста
        .zIndex(0)                 // подстраховка: фото ниже по Z, чем нижние контролы
    }
}

private struct PhotoTile: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))

            if let url {
                AsyncImage(url: url, transaction: .init(animation: .easeInOut)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().scaleEffect(0.9)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()        // заполняем
                            .frame(width: width, height: height)
                            .clipped()             // и строго режем по рамке
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .zIndex(0)
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.system(size: 20, weight: .semibold))
            Text("Нет фото")
                .font(.footnote)
        }
        .foregroundColor(.white.opacity(0.65))
    }
}
