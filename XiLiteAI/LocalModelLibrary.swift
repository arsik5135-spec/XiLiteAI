import Foundation
import SwiftLlama
import SwiftUI
import UniformTypeIdentifiers

struct LocalGGUFModel: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var filename: String
    var source: String
    var addedAt: Date
    var directory: String? = nil

    var displaySource: String { source.isEmpty ? appText("Импортировано из Файлов", "Imported from Files") : source }
}

struct HuggingFaceGGUFFile: Identifiable, Decodable, Hashable {
    let path: String
    let size: Int?
    var id: String { path }
}

private struct GGUFShardInfo {
    let prefix: String
    let indexWidth: Int
    let total: Int
}

@MainActor
final class LocalModelLibrary: ObservableObject {
    static let shared = LocalModelLibrary()

    @Published private(set) var models: [LocalGGUFModel] = []
    @Published var selectedModelID: String {
        didSet {
            UserDefaults.standard.set(selectedModelID, forKey: Self.selectedModelKey)
            if oldValue != selectedModelID {
                Task { await stopAndReleaseModel() }
            }
        }
    }
    @Published private(set) var isDownloading = false
    @Published private(set) var operationMessage: String?
    @Published private(set) var operationError: String?
    @Published private(set) var discoveredFiles: [HuggingFaceGGUFFile] = []

    private static let modelsKey = "localGGUFModels"
    private static let selectedModelKey = "selectedLocalGGUFModel"
    private var llamaService: LlamaService?
    private var loadedModelID: String?

    private init() {
        selectedModelID = UserDefaults.standard.string(forKey: Self.selectedModelKey) ?? ""
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        if let data = UserDefaults.standard.data(forKey: Self.modelsKey),
           let savedModels = try? JSONDecoder().decode([LocalGGUFModel].self, from: data) {
            models = savedModels.filter { modelURL(for: $0) != nil }
        }
        if !models.contains(where: { $0.id == selectedModelID }) {
            selectedModelID = models.first?.id ?? ""
        }
    }

    var selectedModel: LocalGGUFModel? { models.first { $0.id == selectedModelID } }
    var selectedModelURL: URL? { selectedModel.flatMap { modelURL(for: $0) } }

    func setError(_ error: Error) {
        operationError = error.localizedDescription
        operationMessage = nil
    }

    private var modelsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XiLiteAI", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    func importGGUF(from sourceURLs: [URL]) async throws {
        operationError = nil
        guard !sourceURLs.isEmpty else { return }

        let urlsByName = Dictionary(grouping: sourceURLs, by: { $0.lastPathComponent.lowercased() })
        var consumed = Set<String>()
        var groups: [[URL]] = []
        for sourceURL in sourceURLs {
            let originalName = sourceURL.lastPathComponent
            guard originalName.lowercased().hasSuffix(".gguf") else {
                throw ChatError.server(appText("Выберите файл с расширением .gguf.", "Choose a file with the .gguf extension."))
            }
            let key = sourceURL.standardizedFileURL.path
            guard !consumed.contains(key) else { continue }
            if let shard = ggufShardInfo(for: originalName) {
                let expectedNames = (1...shard.total).map { shardName(prefix: shard.prefix, index: $0, info: shard) }
                var group: [URL] = []
                for name in expectedNames {
                    guard let match = urlsByName[name.lowercased()]?.first else {
                        throw ChatError.server(appText("Выбран не весь набор GGUF-частей. Добавь все файлы модели (например, 00001-of-00003 … 00003-of-00003).", "The GGUF shard set is incomplete. Select every model part (for example, 00001-of-00003 through 00003-of-00003)."))
                    }
                    group.append(match)
                    consumed.insert(match.standardizedFileURL.path)
                }
                groups.append(group)
            } else {
                consumed.insert(key)
                groups.append([sourceURL])
            }
        }

        for group in groups {
            let directoryName = UUID().uuidString
            let destinationDirectory = modelsDirectory.appendingPathComponent(directoryName, isDirectory: true)
            let copyItems = group.map { ($0, safeFilename($0.lastPathComponent)) }
            let firstFilename = copyItems[0].1
            do {
                let totalSize = try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
                    var directoryValues = URLResourceValues()
                    directoryValues.isExcludedFromBackup = true
                    var noBackupDirectory = destinationDirectory
                    try? noBackupDirectory.setResourceValues(directoryValues)
                    var totalSize: Int64 = 0
                    for (sourceURL, filename) in copyItems {
                        let destination = destinationDirectory.appendingPathComponent(filename)
                        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
                        defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }
                        try FileManager.default.copyItem(at: sourceURL, to: destination)
                        let handle = try FileHandle(forReadingFrom: destination)
                        defer { try? handle.close() }
                        guard try handle.read(upToCount: 4) == Data("GGUF".utf8),
                              let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                              size > 0 else {
                            throw ChatError.server(appText("Файл GGUF пуст, повреждён или не содержит заголовок GGUF.", "A GGUF file is empty, damaged, or has no GGUF header."))
                        }
                        totalSize += Int64(size)
                    }
                    return totalSize
                }.value
                addModel(filename: firstFilename, source: "", directory: directoryName)
                operationMessage = appText("Модель добавлена (\(formattedSize(totalSize))).", "Model added (\(formattedSize(totalSize))).")
            } catch {
                try? FileManager.default.removeItem(at: destinationDirectory)
                throw error
            }
        }
    }

    func findHuggingFaceGGUFFiles(repository: String, revision: String = "main", token: String = "") async throws {
        operationError = nil
        discoveredFiles = []
        guard let url = huggingFaceTreeURL(repository: repository, revision: revision) else {
            throw ChatError.server(appText("Укажи репозиторий Hugging Face в формате владелец/репозиторий.", "Enter a Hugging Face repository as owner/repository."))
        }
        operationMessage = appText("Ищу GGUF-файлы…", "Searching for GGUF files…")
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty { request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ChatError.server(appText("Hugging Face вернул HTTP \(http.statusCode). Проверь репозиторий и доступ.", "Hugging Face returned HTTP \(http.statusCode). Check the repository and access."))
        }
        let entries = try JSONDecoder().decode([HuggingFaceGGUFFile].self, from: data)
        discoveredFiles = entries.filter { $0.path.lowercased().hasSuffix(".gguf") }.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        operationMessage = discoveredFiles.isEmpty
            ? appText("В репозитории не найдено файлов GGUF.", "No GGUF files were found in this repository.")
            : appText("Найдено GGUF-файлов: \(discoveredFiles.count).", "Found \(discoveredFiles.count) GGUF files.")
    }

    func downloadFromHuggingFace(repository: String, filename: String, revision: String = "main", token: String = "") async throws {
        operationError = nil
        guard huggingFaceDownloadURL(repository: repository, filename: filename, revision: revision) != nil else {
            throw ChatError.server(appText("Проверь репозиторий и путь к GGUF-файлу.", "Check the repository and GGUF file path."))
        }
        guard filename.lowercased().hasSuffix(".gguf") else {
            throw ChatError.server(appText("Для локального запуска поддерживаются только файлы .gguf.", "Only .gguf files are supported for local inference."))
        }
        isDownloading = true
        operationMessage = appText("Скачиваю \(filename)… Размер зависит от модели; загрузка может занять время.", "Downloading \(filename)… Model size varies; this may take a while.")
        defer { isDownloading = false }

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        var directoryValues = URLResourceValues()
        directoryValues.isExcludedFromBackup = true
        var noBackupDirectory = modelsDirectory
        try? noBackupDirectory.setResourceValues(directoryValues)
        let shard = ggufShardInfo(for: URL(fileURLWithPath: filename).lastPathComponent)
        let shardPaths: [String]
        if let shard {
            let parent = (filename as NSString).deletingLastPathComponent
            let expected = (1...shard.total).map { shardName(prefix: shard.prefix, index: $0, info: shard) }
            let remotePaths = Set(discoveredFiles.map(\.path))
            let paths = expected.map { parent.isEmpty || parent == "." ? $0 : "\(parent)/\($0)" }
            guard paths.allSatisfy(remotePaths.contains) else {
                throw ChatError.server(appText("В репозитории отсутствуют части выбранной GGUF-модели.", "The repository is missing one or more shards for this GGUF model."))
            }
            shardPaths = paths
        } else {
            shardPaths = [filename]
        }

        let directoryName = UUID().uuidString
        let destinationDirectory = modelsDirectory.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        var totalSize: Int64 = 0
        do {
            for (index, remotePath) in shardPaths.enumerated() {
                operationMessage = shardPaths.count > 1
                    ? appText("Скачиваю часть \(index + 1) из \(shardPaths.count): \(URL(fileURLWithPath: remotePath).lastPathComponent)…", "Downloading part \(index + 1) of \(shardPaths.count): \(URL(fileURLWithPath: remotePath).lastPathComponent)…")
                    : appText("Скачиваю \(filename)… Размер зависит от модели; загрузка может занять время.", "Downloading \(filename)… Model size varies; this may take a while.")
                guard let shardURL = huggingFaceDownloadURL(repository: repository, filename: remotePath, revision: revision) else {
                    throw ChatError.server(appText("Проверь путь к файлу модели.", "Check the model file path."))
                }
                var shardRequest = URLRequest(url: shardURL)
                shardRequest.timeoutInterval = 900
                shardRequest.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                if !trimmedToken.isEmpty { shardRequest.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization") }
                let (temporaryURL, response) = try await URLSession.shared.download(for: shardRequest)
                guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
                guard (200..<300).contains(http.statusCode) else {
                    throw ChatError.server(appText("Не удалось скачать модель (HTTP \(http.statusCode)). Для закрытых моделей нужен Hugging Face token.", "Model download failed (HTTP \(http.statusCode)). Private models require a Hugging Face token."))
                }
                let size = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size > 0 else { throw ChatError.server(appText("Hugging Face вернул пустой файл.", "Hugging Face returned an empty file.")) }
                try validateGGUFHeader(at: temporaryURL)
                let localName = safeFilename(URL(fileURLWithPath: remotePath).lastPathComponent)
                try FileManager.default.moveItem(at: temporaryURL, to: destinationDirectory.appendingPathComponent(localName))
                totalSize += Int64(size)
            }
            let firstFilename = safeFilename(URL(fileURLWithPath: shardPaths[0]).lastPathComponent)
            let displayName = modelDisplayName(for: URL(fileURLWithPath: filename).lastPathComponent)
            addModel(filename: firstFilename, source: repository, directory: directoryName, name: displayName)
            operationMessage = appText("Модель скачана и выбрана (\(formattedSize(totalSize))).", "Model downloaded and selected (\(formattedSize(totalSize))).")
        } catch {
            try? FileManager.default.removeItem(at: destinationDirectory)
            throw error
        }
    }

    func remove(_ model: LocalGGUFModel) async {
        if selectedModelID == model.id {
            selectedModelID = ""
            await stopAndReleaseModel()
        }
        if let directory = model.directory, isSafeFilename(directory) {
            try? FileManager.default.removeItem(at: modelsDirectory.appendingPathComponent(directory, isDirectory: true))
        } else if let url = modelURL(for: model) {
            try? FileManager.default.removeItem(at: url)
        }
        models.removeAll { $0.id == model.id }
        persistModels()
        if selectedModelID.isEmpty { selectedModelID = models.first?.id ?? "" }
    }

    func streamReply(
        history: [ChatMessage],
        memories: [String],
        customSystemPrompt: String,
        onToken: @MainActor (String) -> Void
    ) async throws -> String {
        guard let model = selectedModel, let url = modelURL(for: model) else {
            throw ChatError.server(appText("Сначала импортируй или скачай GGUF-модель в настройках.", "Import or download a GGUF model in Settings first."))
        }
        if loadedModelID != model.id {
            await stopAndReleaseModel()
            loadedModelID = model.id
            llamaService = LlamaService(modelUrl: url, config: .init(batchSize: 256, maxTokenCount: 4096, useGPU: true))
        }
        guard let llamaService else { throw ChatError.server(appText("Не удалось открыть локальную модель.", "Could not open the local model.")) }

        var messages: [LlamaChatMessage] = [
            LlamaChatMessage(role: .system, content: localSystemPrompt(memories: memories, customSystemPrompt: customSystemPrompt))
        ]
        messages.append(contentsOf: history.compactMap { message in
            guard (message.role == "user" || message.role == "assistant"), !message.content.isEmpty else { return nil }
            return LlamaChatMessage(role: message.role == "user" ? .user : .assistant, content: message.content)
        })
        let stream = try await llamaService.streamCompletion(
            of: messages,
            samplingConfig: LlamaSamplingConfig(temperature: 0.7, seed: UInt32.random(in: 0...UInt32.max))
        )
        var answer = ""
        do {
            for try await token in stream {
                try Task.checkCancellation()
                answer += token
                onToken(token)
            }
        } catch {
            await llamaService.stopCompletion()
            throw error
        }
        return answer
    }

    func stopGeneration() async {
        await llamaService?.stopCompletion()
    }

    private func stopAndReleaseModel() async {
        await llamaService?.stopCompletion()
        llamaService = nil
        loadedModelID = nil
    }

    private func localSystemPrompt(memories: [String], customSystemPrompt: String) -> String {
        var prompt = appText(
            "Ты — Xi Lite, локальный ИИ-помощник. Отвечай на языке пользователя, ясно и полезно. Ты работаешь офлайн и не имеешь доступа к веб-поиску или облачным инструментам.",
            "You are Xi Lite, a local AI assistant. Reply in the user's language, clearly and helpfully. You run offline and have no web-search or cloud-tool access."
        )
        if !memories.isEmpty { prompt += "\n\n" + appText("Память пользователя:\n", "User memories:\n") + memories.joined(separator: "\n") }
        let extra = customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { prompt += "\n\n" + extra }
        return prompt
    }

    private func addModel(filename: String, source: String, directory: String? = nil, name: String? = nil) {
        let id = UUID().uuidString
        models.append(LocalGGUFModel(id: id, name: name ?? modelDisplayName(for: filename), filename: filename, source: source, addedAt: Date(), directory: directory))
        selectedModelID = id
        persistModels()
    }

    private func persistModels() {
        guard let data = try? JSONEncoder().encode(models) else { return }
        UserDefaults.standard.set(data, forKey: Self.modelsKey)
    }

    private func validateGGUFHeader(at url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else {
            throw ChatError.server(appText("Файл не содержит заголовок GGUF и не похож на модель llama.cpp.", "The file has no GGUF header and does not appear to be a llama.cpp model."))
        }
    }

    private func modelURL(for model: LocalGGUFModel) -> URL? {
        guard isSafeFilename(model.filename) else { return nil }
        let baseDirectory: URL
        if let directory = model.directory {
            guard isSafeFilename(directory) else { return nil }
            baseDirectory = modelsDirectory.appendingPathComponent(directory, isDirectory: true)
        } else {
            baseDirectory = modelsDirectory
        }
        let url = baseDirectory.appendingPathComponent(model.filename).standardizedFileURL
        return url.path.hasPrefix(modelsDirectory.standardizedFileURL.path + "/") && FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func ggufShardInfo(for filename: String) -> GGUFShardInfo? {
        let pattern = #"^(.*)-(\d+)-of-(\d+)\.gguf$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
              let prefixRange = Range(match.range(at: 1), in: filename),
              let indexRange = Range(match.range(at: 2), in: filename),
              let totalRange = Range(match.range(at: 3), in: filename),
              let index = Int(filename[indexRange]), let total = Int(filename[totalRange]),
              total > 1, index > 0, index <= total else { return nil }
        return GGUFShardInfo(prefix: String(filename[prefixRange]), indexWidth: filename[indexRange].count, total: total)
    }

    private func shardName(prefix: String, index: Int, info: GGUFShardInfo) -> String {
        let indexText = String(index)
        let totalText = String(info.total)
        let paddedIndex = String(repeating: "0", count: max(0, info.indexWidth - indexText.count)) + indexText
        let paddedTotal = String(repeating: "0", count: max(0, info.indexWidth - totalText.count)) + totalText
        return "\(prefix)-\(paddedIndex)-of-\(paddedTotal).gguf"
    }

    private func modelDisplayName(for filename: String) -> String {
        let withoutShard = filename.replacingOccurrences(of: #"-\d+-of-\d+(?=\.gguf$)"#, with: "", options: [.regularExpression, .caseInsensitive])
        return URL(fileURLWithPath: withoutShard).deletingPathExtension().lastPathComponent
    }

    private func huggingFaceTreeURL(repository: String, revision: String) -> URL? {
        guard isSafeRepository(repository), isSafeRevision(revision) else { return nil }
        var components = URLComponents(string: "https://huggingface.co")
        let repositoryPath = repository.split(separator: "/").map { encodePathSegment(String($0)) }.joined(separator: "/")
        components?.percentEncodedPath = "/api/models/\(repositoryPath)/tree/\(encodePathSegment(revision))"
        components?.queryItems = [URLQueryItem(name: "recursive", value: "true"), URLQueryItem(name: "expand", value: "false"), URLQueryItem(name: "limit", value: "1000")]
        return components?.url
    }

    private func huggingFaceDownloadURL(repository: String, filename: String, revision: String) -> URL? {
        guard isSafeRepository(repository), isSafeRevision(revision), isSafeRemotePath(filename) else { return nil }
        var components = URLComponents(string: "https://huggingface.co")
        let repoPath = repository.split(separator: "/").map { encodePathSegment(String($0)) }.joined(separator: "/")
        let filePath = filename.split(separator: "/").map { encodePathSegment(String($0)) }.joined(separator: "/")
        components?.percentEncodedPath = "/\(repoPath)/resolve/\(encodePathSegment(revision))/\(filePath)"
        components?.queryItems = [URLQueryItem(name: "download", value: "true")]
        return components?.url
    }

    private func isSafeRepository(_ value: String) -> Bool {
        let parts = value.split(separator: "/")
        let valid = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(valid.contains) }
    }

    private func isSafeRevision(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("..") && value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) }
    }

    private func isSafeRemotePath(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        let valid = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-@()[] ,")
        return !value.hasPrefix("/") && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(valid.contains) }
    }

    private func isSafeFilename(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("/") && !value.contains("\\") && value != "." && value != ".."
    }

    private func safeFilename(_ value: String) -> String {
        String(value.map { $0.isLetter || $0.isNumber || "._-() ".contains($0) ? $0 : "_" })
    }

    private func encodePathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? value
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct LocalModelLibraryView: View {
    @EnvironmentObject private var library: LocalModelLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var isImporterPresented = false
    @State private var repository = ""
    @State private var revision = "main"
    @State private var selectedHFFile = ""
    @State private var huggingFaceToken = Keychain.read("huggingface_token") ?? ""
    @State private var rememberToken = false

    private var ggufType: UTType { UTType(filenameExtension: "gguf", conformingTo: .data) ?? .data }

    var body: some View {
        NavigationStack {
            Form {
                Section(appText("Установленные GGUF-модели", "Installed GGUF models")) {
                    if library.models.isEmpty {
                        Text(appText("Импортируй файл .gguf или скачай его из Hugging Face. Для модели из частей выбери все файлы GGUF.", "Import a .gguf file or download one from Hugging Face. For a sharded model, select every GGUF file."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(library.models) { model in
                        HStack(spacing: 10) {
                            Button {
                                library.selectedModelID = model.id
                                UserDefaults.standard.set(true, forKey: "useLocalGGUFModel")
                            } label: {
                                HStack {
                                    Image(systemName: library.selectedModelID == model.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(library.selectedModelID == model.id ? XiPalette.cyan : .secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(model.name).font(.subheadline.weight(.medium)).lineLimit(2)
                                        Text(model.displaySource).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) {
                                Task { await library.remove(model) }
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain)
                                .accessibilityLabel(appText("Удалить модель", "Delete model"))
                        }
                    }
                    Button { isImporterPresented = true } label: {
                        Label(appText("Импортировать GGUF из Файлов…", "Import GGUF from Files…"), systemImage: "folder.badge.plus")
                    }
                    Text(appText("Разбитые модели с именами вида 00001-of-00003 импортируются целиком, если выбрать все части одновременно.", "Sharded models named like 00001-of-00003 are imported as one model when all parts are selected together."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section(appText("Скачать из Hugging Face", "Download from Hugging Face")) {
                    TextField(appText("Репозиторий · owner/model", "Repository · owner/model"), text: $repository)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(appText("Ветка или revision", "Branch or revision"), text: $revision)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(appText("HF token · только для закрытых моделей", "HF token · private models only"), text: $huggingFaceToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle(appText("Сохранить token в Keychain", "Save token in Keychain"), isOn: $rememberToken)
                    HStack {
                        Button {
                            Task {
                                do {
                                    try await library.findHuggingFaceGGUFFiles(repository: repository, revision: revision, token: huggingFaceToken)
                                    selectedHFFile = library.discoveredFiles.first?.path ?? ""
                                } catch { library.setError(error) }
                            }
                        } label: {
                            Label(appText("Найти GGUF", "Find GGUF files"), systemImage: "magnifyingglass")
                        }
                        .disabled(repository.isEmpty || library.isDownloading)
                        Spacer()
                        if library.isDownloading { ProgressView() }
                    }
                    if !library.discoveredFiles.isEmpty {
                        Picker(appText("Файл модели", "Model file"), selection: $selectedHFFile) {
                            ForEach(library.discoveredFiles) { file in
                                Text(file.size.map { "\(file.path) · \(ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file))" } ?? file.path)
                                    .tag(file.path)
                            }
                        }
                        Button {
                            Task {
                                do {
                                    if rememberToken, !huggingFaceToken.isEmpty { try Keychain.save(huggingFaceToken, account: "huggingface_token") }
                                    try await library.downloadFromHuggingFace(repository: repository, filename: selectedHFFile, revision: revision, token: huggingFaceToken)
                                } catch { library.setError(error) }
                            }
                        } label: {
                            Label(appText("Скачать и выбрать модель", "Download and select model"), systemImage: "arrow.down.circle.fill")
                        }
                        .disabled(selectedHFFile.isEmpty || library.isDownloading)
                    }
                    if let message = library.operationMessage {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let error = library.operationError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section {
                    Text(appText(
                        "GGUF-модели часто занимают несколько гигабайт. Скачивай только модели, подходящие по памяти твоему iPhone. Локальная генерация работает на устройстве и не передаёт запрос модели в облако; поддерживается текст, не изображения.",
                        "GGUF models often require several gigabytes. Download models small enough for your iPhone's memory. Local generation runs on-device and sends prompts to no model cloud; text is supported, not images."
                    )).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(appText("Локальные модели", "Local models"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(appText("Готово", "Done")) { dismiss() } } }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [ggufType], allowsMultipleSelection: true) { result in
            Task {
                do {
                    try await library.importGGUF(from: result.get())
                } catch { library.setError(error) }
            }
        }
    }
}
