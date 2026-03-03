import SwiftUI

struct SettingsView: View {
    @State private var autocorrectEnabled: Bool
    @State private var minWordLength: Int
    @State private var excludedApps: [String]
    @State private var customUAWords: [String]
    @State private var customENWords: [String]
    @State private var newUAWord = ""
    @State private var newENWord = ""
    @State private var newExcludedApp = ""

    private let settings = DrukarSettings.shared

    init() {
        let s = DrukarSettings.shared
        _autocorrectEnabled = State(initialValue: s.autocorrectEnabled)
        _minWordLength = State(initialValue: s.minWordLength)
        _excludedApps = State(initialValue: s.excludedApps)
        _customUAWords = State(initialValue: s.customUAWords)
        _customENWords = State(initialValue: s.customENWords)
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Загальне", systemImage: "gearshape") }
            dictionaryTab
                .tabItem { Label("Словник", systemImage: "book") }
            appsTab
                .tabItem { Label("Програми", systemImage: "app.badge") }
        }
        .frame(width: 480, height: 400)
        .padding()
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Автовиправлення помилок", isOn: $autocorrectEnabled)
                    .onChange(of: autocorrectEnabled) { _, val in settings.autocorrectEnabled = val }

                HStack {
                    Text("Мінімальна довжина слова")
                    Spacer()
                    Picker("", selection: $minWordLength) {
                        ForEach(2...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .frame(width: 60)
                    .onChange(of: minWordLength) { _, val in settings.minWordLength = val }
                }
            } header: {
                Text("Детекція")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Caps Lock = примусово English")
                        .foregroundStyle(.secondary)
                    Text("Меню Д → перемикання режимів")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Керування")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Dictionary

    private var dictionaryTab: some View {
        Form {
            Section {
                wordListEditor(
                    words: $customUAWords,
                    newWord: $newUAWord,
                    placeholder: "Додати UA слово...",
                    language: "uk"
                )
            } header: {
                Text("Українські слова (IT-сленг)")
            }

            Section {
                wordListEditor(
                    words: $customENWords,
                    newWord: $newENWord,
                    placeholder: "Add EN word...",
                    language: "en"
                )
            } header: {
                Text("English words")
            }
        }
        .formStyle(.grouped)
    }

    private func wordListEditor(
        words: Binding<[String]>,
        newWord: Binding<String>,
        placeholder: String,
        language: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(placeholder, text: newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addWord(to: words, from: newWord, language: language) }

                Button("Додати") { addWord(to: words, from: newWord, language: language) }
                    .disabled(newWord.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if words.wrappedValue.isEmpty {
                Text("Порожньо")
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    FlowLayout(spacing: 6) {
                        ForEach(words.wrappedValue, id: \.self) { word in
                            wordChip(word) {
                                removeWord(word, from: words, language: language)
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
    }

    private func wordChip(_ word: String, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(word)
                .font(.system(.body, design: .monospaced))
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private func addWord(to words: Binding<[String]>, from newWord: Binding<String>, language: String) {
        let word = newWord.wrappedValue.trimmingCharacters(in: .whitespaces).lowercased()
        guard !word.isEmpty, !words.wrappedValue.contains(word) else { return }
        words.wrappedValue.append(word)
        settings.addCustomWord(word, language: language)
        newWord.wrappedValue = ""
    }

    private func removeWord(_ word: String, from words: Binding<[String]>, language: String) {
        words.wrappedValue.removeAll { $0 == word }
        settings.removeCustomWord(word, language: language)
    }

    // MARK: - Apps Exclusion

    private var appsTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("com.example.app", text: $newExcludedApp)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addExcludedApp() }

                        Button("Додати") { addExcludedApp() }
                            .disabled(newExcludedApp.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    Text("Drukar автоматично вимкнений в Terminal, iTerm2, Kitty, Warp.")
                        .foregroundStyle(.secondary)
                        .font(.callout)

                    if excludedApps.isEmpty {
                        Text("Немає додаткових виключень")
                            .foregroundStyle(.tertiary)
                    } else {
                        List {
                            ForEach(excludedApps, id: \.self) { app in
                                HStack {
                                    Text(app)
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Button(action: { removeExcludedApp(app) }) {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                    }
                }
            } header: {
                Text("Вимкнути Drukar у програмах")
            } footer: {
                Text("Введіть Bundle ID програми. Знайти можна через: osascript -e 'id of app \"Name\"'")
            }
        }
        .formStyle(.grouped)
    }

    private func addExcludedApp() {
        let app = newExcludedApp.trimmingCharacters(in: .whitespaces)
        guard !app.isEmpty, !excludedApps.contains(app) else { return }
        excludedApps.append(app)
        settings.excludedApps = excludedApps
        newExcludedApp = ""
    }

    private func removeExcludedApp(_ app: String) {
        excludedApps.removeAll { $0 == app }
        settings.excludedApps = excludedApps
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (positions, CGSize(width: maxWidth, height: y + rowHeight))
    }
}
