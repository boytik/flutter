import SwiftUI

struct InspectorPhotosView: View {
    let activity: Activity
    var mediaRepo: WorkoutMediaRepository = WorkoutMediaRepositoryImpl()
    var inspectorRepo: InspectorRepository = InspectorRepositoryImpl()

    @State private var beforeURL: URL?
    @State private var afterURL: URL?
    @State private var existingLayer: Int?
    @State private var existingSub: Int?
    @State private var textComment: String = ""
    @State private var level: Int = 0
    @State private var sublevel: Int = 0
    @State private var isSending = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 16) {
            URLPhotoCompareRow(
                beforeURL: beforeURL,
                afterURL: afterURL,
                beforeTitle: "Фото ДО тренировки",
                afterTitle: "Фото ПОСЛЕ тренировки",
                aspect: 3.0/4.0,
                corner: 18
            )
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .zIndex(0)

            if let l = existingLayer, let s = existingSub {
                HStack {
                    Text("Слой: \(l)")
                    Spacer(minLength: 12)
                    Text("Подслой: \(s)")
                    Spacer()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal)
                .zIndex(1)
            } else {
                HStack(spacing: 18) {
                    Text("Выберите слой")
                        .foregroundColor(.white.opacity(0.9))
                    picker(title: "Слой", range: 0...10, selection: $level)
                    picker(title: "Подслой", range: 0...6, selection: $sublevel)
                    Spacer()
                }
                .padding(.horizontal)
                .zIndex(1) // пикеры всегда над фото
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Введите комментарий")
                    .foregroundColor(.white.opacity(0.8))
                TextEditor(text: $textComment)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 140)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.white)
            }
            .padding(.horizontal)

            sendButton // << зелёная без подложки

            if let err = loadError {
                Text(err).foregroundColor(.red).font(.footnote).padding(.horizontal)
            }

            Spacer(minLength: 8)
        }
        .background(Color.clear) // контейнер прозрачен — никакого серого фона
        .onAppear { Task { await loadMedia() } }
    }

    // MARK: - Кнопка отправки (без серого фона)
    private var sendButton: some View {
        HStack {
            Button(action: send) {
                HStack {
                    if isSending { ProgressView().tint(.black) }
                    Text("Отправить").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                // Рисуем фон строго внутри скруглённой формы
                .background(Color.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(.black)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain) // убираем системную подложку/тени
            .disabled(isSending || (existingLayer != nil))
        }
        .padding(.horizontal)
        .background(Color.clear) // контейнер HStack тоже прозрачный
    }

    private func picker(title: String, range: ClosedRange<Int>, selection: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundColor(.white.opacity(0.8))
            Picker(title, selection: selection) {
                ForEach(Array(range), id: \.self) { v in
                    Text("\(v)").tag(v)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .frame(width: 110)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Data
    private func loadMedia() async {
        guard let email = activity.userEmail ?? emailFromPathGuess() else {
            loadError = "Не удалось определить email пользователя."
            return
        }
        do {
            let m = try await mediaRepo.fetch(workoutId: activity.id, email: email)
            await MainActor.run {
                beforeURL = m.before; afterURL = m.after
                existingLayer = m.currentLayerChecked
                existingSub   = m.currentSubLayerChecked
                textComment   = m.comment ?? ""
            }
        } catch {
            await MainActor.run {
                loadError = "Ошибка загрузки фото: \(error.localizedDescription)"
            }
        }
    }

    private func send() {
        Task {
            guard !isSending else { return }
            await MainActor.run { isSending = true }
            let email = activity.userEmail ?? emailFromPathGuess() ?? ""
            do {
                try await inspectorRepo.sendLayers(
                    workoutId: activity.id,
                    email: email,
                    level: level,
                    sublevel: sublevel,
                    comment: textComment
                )
                await MainActor.run {
                    existingLayer = level
                    existingSub   = sublevel
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    loadError = "Не удалось отправить данные: \(error.localizedDescription)"
                }
            }
        }
    }

    private func emailFromPathGuess() -> String? {
        for u in [beforeURL, afterURL] {
            if let url = u {
                let comps = url.pathComponents.filter { $0 != "/" }
                if comps.count >= 3 { return comps[comps.count - 3] }
            }
        }
        return nil
    }
}

// MARK: - Ряд из двух URL-картинок с фиксированной пропорцией
private struct URLPhotoCompareRow: View {
    let beforeURL: URL?
    let afterURL: URL?
    var beforeTitle: String
    var afterTitle: String
    var aspect: CGFloat = 3.0/4.0
    var corner: CGFloat = 18
    var spacing: CGFloat = 12

    var body: some View {
        HStack(spacing: spacing) {
            URLPhotoTileSimple(url: beforeURL,
                               title: beforeTitle,
                               aspect: aspect,
                               corner: corner,
                               titleAccent: Color.white.opacity(0.14))
            URLPhotoTileSimple(url: afterURL,
                               title: afterTitle,
                               aspect: aspect,
                               corner: corner,
                               titleAccent: .green)
        }
        .frame(maxWidth: .infinity)
        .zIndex(0)
    }
}

private struct URLPhotoTileSimple: View {
    let url: URL?
    let title: String
    var aspect: CGFloat = 3.0/4.0
    var corner: CGFloat = 18
    var titleAccent: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.white.opacity(0.06))

            if let url {
                AsyncImage(url: url, transaction: .init(animation: .easeInOut)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(.white)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .clipped()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }

            HStack {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(titleAccent)
                    )
                Spacer()
            }
            .foregroundColor(.white)
            .padding(8)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .aspectRatio(aspect, contentMode: .fit) // высота стабильно считается от ширины
        .frame(maxWidth: .infinity)
        .compositingGroup()                      // корректная маска/слои
        .zIndex(0)
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.white.opacity(0.06))
            VStack(spacing: 6) {
                Image(systemName: "photo").font(.system(size: 20, weight: .semibold))
                Text("Нет фото").font(.footnote)
            }
            .foregroundColor(.white.opacity(0.65))
        }
    }
}
