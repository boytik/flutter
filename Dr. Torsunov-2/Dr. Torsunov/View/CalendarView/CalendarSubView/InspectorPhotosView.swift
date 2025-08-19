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
            HStack(spacing: 16) {
                photoBox(title: "Фото ДО тренировки", url: beforeURL)
                photoBox(title: "Фото ПОСЛЕ тренировки", url: afterURL)
            }
            .frame(height: 180)

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
            } else {
                HStack(spacing: 18) {
                    Text("Выберите слой")
                        .foregroundColor(.white.opacity(0.9))
                    picker(title: "Слой", range: 0...10, selection: $level)
                    picker(title: "Подслой", range: 0...6, selection: $sublevel)
                    Spacer()
                }
                .padding(.horizontal)
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

            Button(action: send) {
                HStack {
                    if isSending { ProgressView().tint(.black) }
                    Text("Отправить").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.green)
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isSending || (existingLayer != nil))
            .padding(.horizontal)

            if let err = loadError {
                Text(err).foregroundColor(.red).font(.footnote).padding(.horizontal)
            }

            Spacer(minLength: 8)
        }
        .onAppear { Task { await loadMedia() } }
    }

    @ViewBuilder
    private func photoBox(title: String, url: URL?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline).foregroundColor(.white.opacity(0.9))
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty: ProgressView().tint(.white)
                        case .success(let img): img.resizable().scaledToFill()
                        case .failure(_): Image(systemName: "photo").resizable().scaledToFit().padding(24)
                        @unknown default: EmptyView()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "photo")
                        .resizable().scaledToFit().padding(24)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
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
