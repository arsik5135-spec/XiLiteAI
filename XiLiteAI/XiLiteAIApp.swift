import SwiftUI
import Security
import AVFoundation
import WebKit
import PhotosUI
import UniformTypeIdentifiers
import Speech
import WidgetKit
import UIKit
import Darwin
import ios_system

struct GroqModel: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String

    static let available: [GroqModel] = [
        .init(id: "llama-3.1-8b-instant", title: "Llama 3.1 8B Instant", detail: "Быстрая · доступ зависит от плана"),
        .init(id: "llama-3.3-70b-versatile", title: "Llama 3.3 70B Versatile", detail: "Универсальная · доступ зависит от плана"),
        .init(id: "openai/gpt-oss-120b", title: "GPT-OSS 120B", detail: "Максимальное качество · универсальная"),
        .init(id: "openai/gpt-oss-20b", title: "GPT-OSS 20B", detail: "Быстрые ответы · инструменты"),
        .init(id: "qwen/qwen3.8-27b", title: "Qwen 3.8 27B", detail: "Рассуждения и универсальные задачи"),
        .init(id: "minimaxai/minimax-m2.7", title: "MiniMax M2.7", detail: "Preview · доступ зависит от плана"),
        .init(id: "openai/gpt-oss-safeguard-20b", title: "GPT-OSS Safeguard 20B", detail: "Безопасность и классификация")
    ]

    static func loadCatalog(apiKey: String) async throws -> [GroqModel] {
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = payload?["error"] as? [String: Any]
            throw ChatError.server(error?["message"] as? String ?? "Groq model catalog error (\(http.statusCode))")
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = payload["data"] as? [[String: Any]] else {
            throw ChatError.invalidResponse
        }

        let knownModels = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        return records.compactMap { record in
            guard let id = record["id"] as? String,
                  record["active"] as? Bool != false else { return nil }
            let normalizedID = id.lowercased()
            guard !["whisper", "tts", "orpheus", "speech", "audio"].contains(where: { normalizedID.contains($0) }) else { return nil }
            return knownModels[id] ?? GroqModel(id: id, title: id, detail: "Groq · доступна по API-ключу")
        }.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }
}

enum AIProvider: String, CaseIterable, Identifiable {
    case groq
    case llm7
    case pollinations

    var id: String { rawValue }
    var title: String {
        switch self {
        case .groq: "Groq"
        case .llm7: "LLM7.io"
        case .pollinations: "Pollinations.ai"
        }
    }
    var apiKeyAccount: String {
        switch self {
        case .groq: "groq_api_key"
        case .llm7: "llm7_api_key"
        case .pollinations: "pollinations_api_key"
        }
    }
    var modelDefaultsKey: String {
        switch self {
        case .groq: "selectedGroqModel"
        case .llm7: "selectedLLM7Model"
        case .pollinations: "selectedPollinationsModel"
        }
    }
    var defaultModelID: String {
        switch self {
        case .groq: "openai/gpt-oss-120b"
        case .llm7: "default"
        case .pollinations: PollinationsModel.defaultModel.id
        }
    }
    var customModelDefaultsKey: String {
        switch self {
        case .groq: "customGroqModelID"
        case .llm7: "customLLM7ModelID"
        case .pollinations: "customPollinationsModelID"
        }
    }

    static func supportsImages(provider: AIProvider, model: String) -> Bool {
        let value = model.lowercased()
        return ["gpt-4o", "gpt-4.1", "gpt-4.5", "gemini", "claude", "llama-4", "llava", "vision", "pixtral", "qwen2-vl", "qwen2.5-vl", "qwen-vl", "ministral-3"].contains(where: value.contains)
    }
}

struct LLM7Model: Identifiable, Hashable {
    let id: String

    static func loadCatalog() async throws -> [LLM7Model] {
        let url = URL(string: "https://api.llm7.io/v1/models")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = payload["data"] as? [[String: Any]] else {
            throw ChatError.invalidResponse
        }
        return records.compactMap { record in
            guard record["model_type"] as? String == "chat",
                  (record["schema_endpoints"] as? [String])?.contains("openai") == true,
                  let id = record["id"] as? String else { return nil }
            return LLM7Model(id: id)
        }.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }
}

struct PollinationsModel: Identifiable, Hashable {
    let id: String
    let title: String

    static let defaultModel = PollinationsModel(id: "openai", title: "OpenAI · по умолчанию")

    static func loadCatalog(apiKey: String) async throws -> [PollinationsModel] {
        var request = URLRequest(url: URL(string: "https://gen.pollinations.ai/v1/models")!)
        request.timeoutInterval = 25
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = payload?["error"] as? [String: Any]
            throw ChatError.server(error?["message"] as? String ?? "Pollinations model catalog error (\(http.statusCode))")
        }

        let decoded = try JSONSerialization.jsonObject(with: data)
        let records: [[String: Any]]
        if let list = decoded as? [[String: Any]] {
            records = list
        } else if let payload = decoded as? [String: Any], let list = payload["data"] as? [[String: Any]] {
            records = list
        } else {
            throw ChatError.invalidResponse
        }

        let catalogModels = records.flatMap { record -> [PollinationsModel] in
            guard record["category"] as? String == "text",
                  (record["supported_endpoints"] as? [String])?.contains("/v1/chat/completions") == true,
                  let id = (record["id"] as? String) ?? (record["name"] as? String) else { return [] }
            let title = record["title"] as? String ?? id
            var models = [PollinationsModel(id: id, title: title)]
            let aliases = record["aliases"] as? [String] ?? []
            models.append(contentsOf: aliases.map { alias in
                PollinationsModel(
                    id: alias,
                    title: alias == defaultModel.id ? "OpenAI · по умолчанию" : "\(alias) · \(title)"
                )
            })
            return models
        }
        var uniqueModels = Dictionary(catalogModels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        uniqueModels[defaultModel.id] = defaultModel
        return uniqueModels.values.sorted {
            if $0.id == defaultModel.id { return true }
            if $1.id == defaultModel.id { return false }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}

enum GroqSpeechModel {
    static let russianRecognitionModels: [(id: String, title: String, detail: String)] = [
        ("whisper-large-v3", "Whisper Large V3", "Максимальная точность · русский"),
        ("whisper-large-v3-turbo", "Whisper Large V3 Turbo", "Быстрее · мультиязычная")
    ]
}

func isValidGroqModelID(_ value: String) -> Bool {
    guard !value.isEmpty else { return false }
    let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/:")
    return value.unicodeScalars.allSatisfy(allowedCharacters.contains)
}

func appText(_ russian: String, _ english: String) -> String {
    UserDefaults.standard.string(forKey: "appLanguage") == "en" ? english : russian
}

func resizedJPEG(_ image: UIImage, maxSide: CGFloat = 1600) -> Data? {
    let scale = min(1, maxSide / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.jpegData(withCompressionQuality: 0.65) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
}

@main
struct XiLiteAIApp: App {
    @StateObject private var store = ChatStore()
    @StateObject private var account = AccountSessionStore()
    @StateObject private var localModels = LocalModelLibrary.shared
    @AppStorage("isDarkTheme") private var isDarkTheme = true
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedSetup {
                    FirstRunSetupView()
                } else if account.isCheckingSession {
                    ProgressView(appText("Проверяю аккаунт…", "Checking account…"))
                } else if account.isAuthenticated {
                    ChatHomeView()
                        .environmentObject(store)
                        .environmentObject(account)
                        .environmentObject(localModels)
                        .onAppear { store.isPremium = account.isPremium }
                        .onChange(of: account.isPremium) { _, value in store.isPremium = value }
                } else {
                    AccountLoginView().environmentObject(account)
                }
            }
            .preferredColorScheme(isDarkTheme ? .dark : .light)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && account.isAuthenticated { Task { await account.refreshAccount() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: .xiAccountSessionRejected)) { _ in
                Task { await account.refreshAccount() }
            }
        }
    }
}

struct ChatMessage: Identifiable, Codable {
    var id = UUID()
    var role: String
    var content: String
    var createdAt = Date()
    var imageData: [String]? = nil
    var files: [ChatFileAttachment]? = nil
}

struct ChatFileAttachment: Identifiable, Codable, Hashable {
    var id = UUID()
    var filename: String
    var contentsBase64: String
}

struct ChatActivity: Identifiable {
    var id = UUID()
    var title: String
    var url: String?
}

struct TerminalCommandResult: @unchecked Sendable {
    let output: String
    let exitCode: Int32
    let files: [TerminalOutputFile]
}

struct TerminalOutputFile: @unchecked Sendable {
    let path: String
    let data: Data
}

enum XiLocalTerminal {
    private static let executionQueue = DispatchQueue(label: "com.xilite.ai.terminal", qos: .userInitiated)
    private static var didLoadCommandCatalogs = false
    private static var didConfigurePythonEnvironment = false

    static func prepareWorkspace() {
        let root = workspaceURL
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        initializeEnvironment()
        configurePythonEnvironment()
        if !didLoadCommandCatalogs {
            if let dictionary = Bundle.main.path(forResource: "commandDictionary", ofType: "plist") { _ = addCommandList(dictionary) }
            if let extraDictionary = Bundle.main.path(forResource: "extraCommandsDictionary", ofType: "plist") { _ = addCommandList(extraDictionary) }
            didLoadCommandCatalogs = true
        }
        _ = ios_setMiniRootURL(root)
        _ = ios_setAllowedPaths([root.path])
        ios_setDirectoryURL(root)
    }

    static func execute(_ command: String) async -> TerminalCommandResult {
        await withCheckedContinuation { continuation in
            executionQueue.async {
                continuation.resume(returning: executeSynchronously(command))
            }
        }
    }

    private static var workspaceURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XiLiteAI", isDirectory: true)
    }

    private static var pythonPackagesURL: URL {
        workspaceURL.appendingPathComponent(".python-packages", isDirectory: true)
    }

    private static func configurePythonEnvironment() {
        guard !didConfigurePythonEnvironment else { return }
        try? FileManager.default.createDirectory(at: pythonPackagesURL, withIntermediateDirectories: true)

        let packagePath = pythonPackagesURL.path
        let existingPythonPaths = getenv("PYTHONPATH").map { String(cString: $0) }
            .map { $0.split(separator: ":").map(String.init) } ?? []
        if !existingPythonPaths.contains(packagePath) {
            _ = setenv("PYTHONPATH", (existingPythonPaths + [packagePath]).joined(separator: ":"), 1)
        }
        let userBase = workspaceURL.appendingPathComponent(".python-user", isDirectory: true).path
        _ = setenv("PYTHONUSERBASE", userBase, 1)
        let gitConfigPath = workspaceURL.appendingPathComponent(".gitconfig").path
        _ = setenv("GIT_CONFIG_GLOBAL", gitConfigPath, 1)
        didConfigurePythonEnvironment = true
    }

    private static func executeSynchronously(_ input: String) -> TerminalCommandResult {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, command.count <= 24_000, !command.contains("\0") else {
            return TerminalCommandResult(output: appText("Команда пустая или слишком длинная.", "Command is empty or too long."), exitCode: 2, files: [])
        }
        prepareWorkspace()
        let before = workspaceFiles()
        if let heredoc = parseSafeHeredoc(command) {
            do {
                try writeWorkspaceFile(heredoc.path, contents: heredoc.contents, append: false)
                return TerminalCommandResult(output: appText("Сохранено: \(heredoc.path)", "Saved: \(heredoc.path)"), exitCode: 0, files: changedWorkspaceFiles(since: before))
            } catch {
                return TerminalCommandResult(output: error.localizedDescription, exitCode: 1, files: [])
            }
        }
        if let writeOperation = parseSafeWrite(command) {
            do {
                try writeWorkspaceFile(writeOperation.path, contents: writeOperation.contents, append: writeOperation.append)
                return TerminalCommandResult(output: appText("Сохранено: \(writeOperation.path)", "Saved: \(writeOperation.path)"), exitCode: 0, files: changedWorkspaceFiles(since: before))
            } catch {
                return TerminalCommandResult(output: error.localizedDescription, exitCode: 1, files: [])
            }
        }
        let commandName = command.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""

        if commandName == "git", let gitConfigResult = executeGitConfig(command, before: before) {
            return gitConfigResult
        }

        if ["pip", "pip3", "pip3.9"].contains(commandName) {
            let pipArguments = String(command.dropFirst(commandName.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return executePip(pipArguments, before: before)
        }

        if commandName == "git" {
            let gitArguments = String(command.dropFirst(commandName.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let availability = executeRuntimeCommand("python3 -c \"import dulwich\"", before: before)
            var installOutput = ""
            if availability.exitCode != 0 {
                let installation = executePip("install dulwich==0.22.8", before: before)
                guard installation.exitCode == 0 else {
                    return TerminalCommandResult(
                        output: installation.output,
                        exitCode: installation.exitCode,
                        files: changedWorkspaceFiles(since: before)
                    )
                }
                installOutput = installation.output
            }

            if gitArguments == "--version" || gitArguments == "-v" {
                let version = executeRuntimeCommand("python3 -c \"import dulwich; print('git (Dulwich) ' + '.'.join(map(str, dulwich.__version__)))\"", before: before)
                return TerminalCommandResult(output: installOutput + version.output, exitCode: version.exitCode, files: changedWorkspaceFiles(since: before))
            }

            if let gitSubcommandResult = executeGitSubcommand(gitArguments, before: before) {
                return TerminalCommandResult(
                    output: installOutput + gitSubcommandResult.output,
                    exitCode: gitSubcommandResult.exitCode,
                    files: changedWorkspaceFiles(since: before)
                )
            }

            let gitCommand = "python3 -m dulwich" + (gitArguments.isEmpty ? " help -a" : " \(gitArguments)")
            let result = executeRuntimeCommand(gitCommand, before: before)
            return TerminalCommandResult(
                output: installOutput + result.output,
                exitCode: result.exitCode,
                files: changedWorkspaceFiles(since: before)
            )
        }

        return executeRuntimeCommand(command, before: before)
    }

    private static func executeGitSubcommand(_ input: String, before: [String: Date]) -> TerminalCommandResult? {
        let arguments = shellArguments(input)
        guard let subcommand = arguments.first, ["branch", "checkout", "switch"].contains(subcommand) else { return nil }
        let encodedArguments = (try? JSONSerialization.data(withJSONObject: Array(arguments.dropFirst())))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let script = #"""
import json, sys
from dulwich import porcelain
args = json.loads(__ARGS__)
repo = '.'
try:
    if '__COMMAND__' == 'branch':
        current = porcelain.active_branch(repo)
        if not args or args[0] == '--list' or args[0] == '-a':
            for branch in sorted(porcelain.branch_list(repo)):
                name = branch.decode('utf-8', 'replace') if isinstance(branch, bytes) else str(branch)
                print((' * ' if name == current.decode('utf-8', 'replace') else '   ') + name)
        elif args[0] in ('-d', '-D', '--delete') and len(args) > 1:
            name = args[1]
            if name.encode() == current:
                raise ValueError('cannot delete the checked-out branch')
            porcelain.branch_delete(repo, name)
        else:
            names = [arg for arg in args if not arg.startswith('-')]
            if not names:
                raise ValueError('branch name is required')
            start = names[1] if len(names) > 1 else 'HEAD'
            porcelain.branch_create(repo, names[0], objectish=start, force='-f' in args)
    else:
        force = '-f' in args or '--force' in args
        create = args[args.index('-b') + 1] if '-b' in args and args.index('-b') + 1 < len(args) else (args[args.index('-c') + 1] if '-c' in args and args.index('-c') + 1 < len(args) else None)
        target = args[-1] if args else None
        if create and target == create:
            target = 'HEAD'
        if not target:
            raise ValueError('a branch or commit is required')
        status = porcelain.status(repo)
        dirty = any(status.staged.values()) or bool(status.unstaged) or bool(status.untracked)
        if dirty and not force:
            raise ValueError('working tree has changes; commit/stash them or use -f to discard')
        if create:
            porcelain.branch_create(repo, create, objectish=target)
            target = create
        porcelain.reset(repo, mode='hard', treeish=target)
        porcelain.update_head(repo, target)
except Exception as error:
    print('fatal: ' + str(error), file=sys.stderr)
    sys.exit(1)
"""#.replacingOccurrences(of: "__COMMAND__", with: subcommand)
            .replacingOccurrences(of: "__ARGS__", with: encodedArguments)
        let command = "python3 -c \(shellQuoted(script))"
        return executeRuntimeCommand(command, before: before)
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func executeGitConfig(_ command: String, before: [String: Date]) -> TerminalCommandResult? {
        let arguments = String(command.dropFirst("git".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard arguments == "config" || arguments.hasPrefix("config ") else { return nil }
        let fields = shellArguments(String(arguments.dropFirst("config".count)))
        guard fields.first == "--global" else {
            return TerminalCommandResult(
                output: appText("Поддерживаются только `git config --global user.name` и `user.email`.", "Only `git config --global user.name` and `user.email` are supported."),
                exitCode: 2,
                files: []
            )
        }
        guard fields.count == 2 || fields.count == 3 else {
            return TerminalCommandResult(
                output: appText("Использование: git config --global user.name|user.email [значение]", "Usage: git config --global user.name|user.email [value]"),
                exitCode: 2,
                files: []
            )
        }
        guard ["user.name", "user.email"].contains(fields[1]) else {
            return TerminalCommandResult(
                output: appText("Использование: git config --global user.name|user.email [значение]", "Usage: git config --global user.name|user.email [value]"),
                exitCode: 2,
                files: []
            )
        }

        let configURL = workspaceURL.appendingPathComponent(".gitconfig")
        var config = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let key = fields[1] == "user.name" ? "name" : "email"
        if fields.count == 2 {
            let pattern = #"(?m)^\s*"# + key + #"\s*=\s*(.*?)\s*$"#
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: config, range: NSRange(config.startIndex..., in: config)),
                  let valueRange = Range(match.range(at: 1), in: config) else {
                return TerminalCommandResult(output: "", exitCode: 1, files: [])
            }
            return TerminalCommandResult(output: String(config[valueRange]) + "\n", exitCode: 0, files: [])
        }

        let value = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 200, !value.contains("\n"), !value.contains("\r") else {
            return TerminalCommandResult(output: appText("Недопустимое значение Git config.", "Invalid Git config value."), exitCode: 2, files: [])
        }
        if !config.hasPrefix("[user]") {
            config = "[user]\n"
        }
        let pattern = #"(?m)^\s*"# + key + #"\s*=.*(?:\n|$)"#
        if let expression = try? NSRegularExpression(pattern: pattern),
           let range = Range(expression.rangeOfFirstMatch(in: config, range: NSRange(config.startIndex..., in: config)), in: config),
           !range.isEmpty {
            config.replaceSubrange(range, with: "\t\(key) = \(value)\n")
        } else {
            if !config.hasSuffix("\n") { config += "\n" }
            config += "\t\(key) = \(value)\n"
        }
        do {
            try Data(config.utf8).write(to: configURL, options: .atomic)
            return TerminalCommandResult(output: appText("Сохранено в настройках Git.", "Saved Git setting."), exitCode: 0, files: changedWorkspaceFiles(since: before))
        } catch {
            return TerminalCommandResult(output: error.localizedDescription, exitCode: 1, files: [])
        }
    }

    private static func shellArguments(_ input: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false
        for character in input {
            if escaping {
                current.append(character)
                escaping = false
            } else if character == "\\", quote != "'" {
                escaping = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil } else { current.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { arguments.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if escaping { current.append("\\") }
        if !current.isEmpty { arguments.append(current) }
        return arguments
    }

    private static func executePip(_ pipArguments: String, before: [String: Date]) -> TerminalCommandResult {
            let pipCheck = executeRuntimeCommand("python3 -m pip --version", before: before)
            if pipCheck.exitCode != 0 {
                let bootstrap = executeRuntimeCommand("python3 -m ensurepip --user", before: before)
                guard bootstrap.exitCode == 0 else {
                    return TerminalCommandResult(
                        output: appText("Не удалось подготовить pip.\n", "Could not bootstrap pip.\n") + bootstrap.output,
                        exitCode: bootstrap.exitCode,
                        files: changedWorkspaceFiles(since: before)
                    )
                }
            }

            var commandToExecute = "python3 -m pip" + (pipArguments.isEmpty ? "" : " \(pipArguments)")
            if pipArguments == "install" || pipArguments.hasPrefix("install ") || pipArguments.hasPrefix("install\t") {
                let target = "\"\(pythonPackagesURL.path)\""
                commandToExecute += " --target \(target) --platform any --python-version 3.9 --implementation py --abi none --only-binary=:all:"
            }
        return executeRuntimeCommand(commandToExecute, before: before)
    }

    private static func executeRuntimeCommand(_ command: String, before: [String: Date]) -> TerminalCommandResult {
        let commandName = command.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let commandIsRegistered = commandName.withCString { ios_executable($0) != 0 }
        guard commandIsRegistered else {
            return TerminalCommandResult(output: appText("Команда «\(commandName)» отсутствует в подключённом ios_system runtime.", "Command ‘\(commandName)’ is not included in the bundled ios_system runtime."), exitCode: 127, files: [])
        }
        _ = ios_setMiniRootURL(workspaceURL)
        _ = ios_setAllowedPaths([workspaceURL.path])
        ios_setDirectoryURL(workspaceURL)
        guard let pipe = (command + " 2>&1").withCString({ ios_popen($0, "r") }) else {
            return TerminalCommandResult(output: appText("Не удалось запустить локальную команду.", "Could not start the local command."), exitCode: 1, files: [])
        }
        var output = Data()
        var buffer = [CChar](repeating: 0, count: 1024)
        while output.count < 16_384 {
            let readCount = buffer.withUnsafeMutableBufferPointer { pointer in
                fread(pointer.baseAddress, 1, pointer.count, pipe)
            }
            if readCount == 0 { break }
            output.append(contentsOf: buffer.prefix(readCount).map { UInt8(bitPattern: $0) })
        }
        _ = fclose(pipe)
        let text = String(decoding: output, as: UTF8.self)
        return TerminalCommandResult(output: text.isEmpty ? appText("Команда выполнена без вывода.", "Command completed with no output.") : text, exitCode: ios_getCommandStatus(), files: changedWorkspaceFiles(since: before))
    }

    private static func writeWorkspaceFile(_ relativePath: String, contents: String, append: Bool) throws {
        guard isTerminalSafeRelativePath(relativePath) else { throw ChatError.server(appText("Недопустимый путь файла.", "Invalid file path.")) }
        let target = workspaceURL.appendingPathComponent(relativePath).standardizedFileURL
        guard isContained(target, in: workspaceURL) else { throw ChatError.server(appText("Путь выходит за пределы рабочего пространства XiLiteAI.", "Path escapes the XiLiteAI workspace.")) }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if append, FileManager.default.fileExists(atPath: target.path) {
            let handle = try FileHandle(forWritingTo: target)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(contents.utf8))
            try handle.close()
        } else {
            try Data(contents.utf8).write(to: target, options: .atomic)
        }
    }

    private static func workspaceFiles() -> [String: Date] {
        let root = workspaceURL
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [:] }
        var files: [String: Date] = [:]
        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]), values.isRegularFile == true else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            files[relative] = values.contentModificationDate ?? .distantPast
        }
        return files
    }

    private static func changedWorkspaceFiles(since before: [String: Date]) -> [TerminalOutputFile] {
        let root = workspaceURL
        var includedBytes = 0
        return workspaceFiles().compactMap { path, date in
            guard before[path] == nil || date > (before[path] ?? .distantPast),
                  let data = try? Data(contentsOf: root.appendingPathComponent(path)),
                  data.count <= 4_000_000, includedBytes + data.count <= 5_000_000 else { return nil }
            includedBytes += data.count
            return TerminalOutputFile(path: path, data: data)
        }.prefix(6).map { $0 }
    }

    private static func parseSafeHeredoc(_ command: String) -> (path: String, contents: String)? {
        let pattern = #"^cat\s*>\s*([A-Za-z0-9_./-]+)\s*<<['\"]?([A-Za-z0-9]+)['\"]?\r?\n([\s\S]*?)\r?\n\2\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
              let pathRange = Range(match.range(at: 1), in: command),
              let contentsRange = Range(match.range(at: 3), in: command) else { return nil }
        let path = String(command[pathRange])
        guard isTerminalSafeRelativePath(path) else { return nil }
        return (path, String(command[contentsRange]))
    }

    private static func parseSafeWrite(_ command: String) -> (contents: String, path: String, append: Bool)? {
        let pattern = #"^(echo|printf)\s+(.+?)\s*(>>|>)\s*([A-Za-z0-9_./-]+)$"#
        guard let range = command.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(command[range])
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: match, range: NSRange(match.startIndex..., in: match)),
              let contentsRange = Range(result.range(at: 2), in: match),
              let operationRange = Range(result.range(at: 3), in: match),
              let pathRange = Range(result.range(at: 4), in: match) else { return nil }
        var contents = String(match[contentsRange])
        if contents.count >= 2, let first = contents.first, (first == "\"" || first == "'"), contents.last == first {
            contents.removeFirst()
            contents.removeLast()
        }
        let relativePath = String(match[pathRange])
        guard isTerminalSafeRelativePath(relativePath) else { return nil }
        if match.hasPrefix("echo ") && !contents.hasSuffix("\n") { contents += "\n" }
        return (contents, relativePath, String(match[operationRange]) == ">>")
    }

    private static func isTerminalSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains(".."), !path.contains("\\") else { return false }
        return path.split(separator: "/").allSatisfy { !$0.hasPrefix(".") }
    }

    private static func isContained(_ file: URL, in root: URL) -> Bool {
        file.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/")
    }
}

struct ChatFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .zip] }
    let contents: Data

    init(contents: Data) { self.contents = contents }

    init(configuration: ReadConfiguration) throws {
        contents = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: contents)
    }
}

enum XiPalette {
    private static let baseCyan = Color(red: 0.08, green: 0.96, blue: 1)
    private static let baseRed = Color(red: 1, green: 0.12, blue: 0.28)
    private static let baseViolet = Color(red: 0.55, green: 0.28, blue: 1)
    static var cyan: Color { selectedColors.first ?? baseCyan }
    static var red: Color { selectedColors.last ?? baseRed }
    static var violet: Color { selectedColors.dropFirst().first ?? baseViolet }
    static let gradientOptions: [(id: String, titleRU: String, titleEN: String, colors: [Color])] = [
        ("xi", "Xi · бирюзовый / фиолетовый / красный", "Xi · cyan / violet / red", [baseCyan, baseViolet, baseRed]),
        ("ocean", "Океан · синий / бирюзовый", "Ocean · blue / cyan", [Color(red: 0.12, green: 0.38, blue: 1), baseCyan]),
        ("sunset", "Закат · оранжевый / розовый", "Sunset · orange / pink", [Color.orange, Color.pink, baseViolet]),
        ("forest", "Лес · зелёный / бирюзовый", "Forest · green / cyan", [Color.green, baseCyan]),
        ("mono", "Монохром · серебряный", "Monochrome · silver", [Color.white, Color.gray])
    ]
    static var selectedColors: [Color] {
        let id = UserDefaults.standard.string(forKey: "gradientPalette") ?? "xi"
        if id == "custom" {
            return [
                Color(hex: UserDefaults.standard.string(forKey: "customGradientColor1") ?? "12F4FF"),
                Color(hex: UserDefaults.standard.string(forKey: "customGradientColor2") ?? "8C47FF"),
                Color(hex: UserDefaults.standard.string(forKey: "customGradientColor3") ?? "FF315A")
            ]
        }
        return gradientOptions.first(where: { $0.id == id })?.colors ?? gradientOptions[0].colors
    }
    static var gradient: LinearGradient {
        LinearGradient(colors: selectedColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0x12F4FF
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255, opacity: 1)
    }
}

struct ChatThread: Identifiable, Codable {
    var id = UUID()
    var title: String
    var updatedAt = Date()
    var messages: [ChatMessage] = []
    var isPinned = false
    var hasGeneratedTitle = false

    private enum CodingKeys: String, CodingKey {
        case id, title, updatedAt, messages, isPinned, hasGeneratedTitle
    }

    init(id: UUID = UUID(), title: String, updatedAt: Date = Date(), messages: [ChatMessage] = [], isPinned: Bool = false, hasGeneratedTitle: Bool = false) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.messages = messages
        self.isPinned = isPinned
        self.hasGeneratedTitle = hasGeneratedTitle
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? appText("Новый чат", "New chat")
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        messages = try values.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        hasGeneratedTitle = try values.decodeIfPresent(Bool.self, forKey: .hasGeneratedTitle) ?? false
    }

    var exportText: String {
        messages.map { message in
            "\(message.role == "user" ? "You" : "Xi Lite"):\n\(message.content)" + ((message.imageData?.isEmpty == false) ? "\n[Image attached]" : "")
        }.joined(separator: "\n\n")
    }
}

@MainActor
final class ChatStore: ObservableObject {
    @Published var chats: [ChatThread] {
        didSet { persist(chats, key: "chats") }
    }
    @Published var selectedChatID: UUID? {
        didSet { UserDefaults.standard.set(selectedChatID?.uuidString, forKey: "selectedChatID") }
    }
    @Published var memories: [String] {
        didSet { persist(memories, key: "memories") }
    }
    @Published var customSystemPrompt: String {
        didSet { UserDefaults.standard.set(customSystemPrompt, forKey: "customSystemPrompt") }
    }
    @Published var selectedProvider: AIProvider {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: "selectedAIProvider")
            selectedModelID = UserDefaults.standard.string(forKey: selectedProvider.modelDefaultsKey)
                ?? selectedProvider.defaultModelID
        }
    }
    @Published var selectedModelID: String {
        didSet { UserDefaults.standard.set(selectedModelID, forKey: selectedProvider.modelDefaultsKey) }
    }
    @Published var isSending = false
    @Published var isPremium = false
    @Published private(set) var dailyMessageCount: Int
    @Published var statusMessage: String?
    @Published var activityItems: [ChatActivity] = []
    @Published var clarificationQuestion: String?
    @Published var errorMessage: String?
    private var activeGenerationTask: Task<Void, Error>?
    private var clarificationContinuation: CheckedContinuation<String, Error>?
    private var lastResponseHapticCount = 0

    init() {
        chats = Self.load([ChatThread].self, key: "chats") ?? []
        memories = Self.load([String].self, key: "memories") ?? []
        customSystemPrompt = UserDefaults.standard.string(forKey: "customSystemPrompt") ?? ""
        dailyMessageCount = Self.storedDailyMessageCount()
        let provider = AIProvider(rawValue: UserDefaults.standard.string(forKey: "selectedAIProvider") ?? "groq") ?? .groq
        selectedProvider = provider
        let storedModel = UserDefaults.standard.string(forKey: provider.modelDefaultsKey)
        let savedModel = provider == .pollinations && storedModel == "gemini-flash"
            ? provider.defaultModelID
            : storedModel ?? provider.defaultModelID
        selectedModelID = isValidGroqModelID(savedModel) ? savedModel : provider.defaultModelID
        if let savedID = UserDefaults.standard.string(forKey: "selectedChatID") {
            selectedChatID = UUID(uuidString: savedID)
        } else {
            selectedChatID = nil
        }
        if let selectedChatID, !chats.contains(where: { $0.id == selectedChatID }) {
            self.selectedChatID = chats.first?.id
        }
    }

    var currentChat: ChatThread? { chats.first(where: { $0.id == selectedChatID }) }
    var canCreateChat: Bool { isPremium || chats.count < 10 }

    private static func localDayKey(_ date: Date = Date()) -> String {
        let components = Calendar.autoupdatingCurrent.dateComponents([.era, .year, .month, .day], from: date)
        return "\(components.era ?? 1)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private static func storedDailyMessageCount() -> Int {
        guard UserDefaults.standard.string(forKey: "dailyMessageDate") == localDayKey() else { return 0 }
        return UserDefaults.standard.integer(forKey: "dailyMessageCount")
    }

    private func reserveDailyMessage() -> Bool {
        let today = Self.localDayKey()
        if UserDefaults.standard.string(forKey: "dailyMessageDate") != today {
            UserDefaults.standard.set(today, forKey: "dailyMessageDate")
            UserDefaults.standard.set(0, forKey: "dailyMessageCount")
            dailyMessageCount = 0
        }
        guard isPremium || dailyMessageCount < 100 else {
            errorMessage = appText("Бесплатный дневной лимит исчерпан.", "The free daily message limit has been reached.")
            return false
        }
        if !isPremium {
            dailyMessageCount += 1
            UserDefaults.standard.set(dailyMessageCount, forKey: "dailyMessageCount")
        }
        return true
    }

    @discardableResult
    func createChat() -> UUID? {
        guard canCreateChat else { return nil }
        let chat = ChatThread(title: appText("Новый чат", "New chat"))
        chats.insert(chat, at: 0)
        selectedChatID = chat.id
        return chat.id
    }

    func select(_ chat: ChatThread) { selectedChatID = chat.id }

    func delete(_ chat: ChatThread) {
        chats.removeAll { $0.id == chat.id }
        if selectedChatID == chat.id { selectedChatID = chats.first?.id }
    }

    func send(_ text: String, imageData: [String] = [], webSearch: Bool, appendingUserMessage: Bool = true, onReply: @escaping @MainActor (String) -> Void = { _ in }) async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!prompt.isEmpty || !imageData.isEmpty), !isSending else { return }
        let usesLocalModel = UserDefaults.standard.bool(forKey: "useLocalGGUFModel")
        if usesLocalModel, !isPremium {
            errorMessage = appText("Локальные GGUF-модели доступны в Pro.", "On-device GGUF models are available with Pro.")
            return
        }
        if usesLocalModel, LocalModelLibrary.shared.selectedModel == nil {
            errorMessage = appText("Сначала добавь GGUF-модель в настройках локальных моделей.", "Add a GGUF model in Local Models settings first.")
            return
        }
        if usesLocalModel, !imageData.isEmpty {
            errorMessage = appText("Локальные GGUF-модели сейчас поддерживают текст, но не изображения.", "Local GGUF models currently support text, not images.")
            return
        }
        if usesLocalModel, currentChat?.messages.contains(where: { $0.imageData?.isEmpty == false }) == true {
            errorMessage = appText("В этой переписке есть изображения. Открой новый чат или выбери облачную vision-модель.", "This conversation contains images. Start a new chat or choose a cloud vision model.")
            return
        }
        if !usesLocalModel, selectedProvider == .pollinations && !isPremium {
            errorMessage = appText("Pollinations.ai доступен в Pro.", "Pollinations.ai is available with Pro.")
            return
        }
        if !imageData.isEmpty && !AIProvider.supportsImages(provider: selectedProvider, model: selectedModelID) {
            errorMessage = appText("Выбранная модель не поддерживает изображения. Выбери vision-модель.", "The selected model does not support images. Choose a vision model.")
            return
        }
        if appendingUserMessage, selectedChatID == nil && !canCreateChat {
            errorMessage = appText("Бесплатный лимит — 10 чатов. Подключите Pro, чтобы создавать чаты без ограничений.", "Free plan limit: 10 chats. Get Pro to create unlimited chats.")
            return
        }
        guard reserveDailyMessage() else { return }
        let chatID: UUID
        if let selectedChatID {
            chatID = selectedChatID
        } else if let createdChatID = createChat() {
            chatID = createdChatID
        } else {
            errorMessage = appText("Бесплатный лимит — 10 чатов. Подключите Pro, чтобы создавать чаты без ограничений.", "Free plan limit: 10 chats. Get Pro to create unlimited chats.")
            return
        }
        guard let index = chats.firstIndex(where: { $0.id == chatID }) else { return }

        if appendingUserMessage {
            chats[index].messages.append(ChatMessage(role: "user", content: prompt, imageData: imageData.isEmpty ? nil : imageData))
        }
        if appendingUserMessage, chats[index].messages.filter({ $0.role == "user" }).count == 1 {
            chats[index].title = String(prompt.prefix(34))
        }
        chats[index].updatedAt = Date()
        let history = chats[index].messages
        let assistantID = UUID()
        chats[index].messages.append(ChatMessage(id: assistantID, role: "assistant", content: ""))
        lastResponseHapticCount = 0
        isSending = true
        statusMessage = webSearch ? appText("Ищу в интернете…", "Searching the web…") : appText("Думаю…", "Thinking…")
        activityItems.removeAll()
        errorMessage = nil
        defer {
            isSending = false
            statusMessage = nil
            activityItems.removeAll()
            clarificationQuestion = nil
            activeGenerationTask = nil
        }

        do {
            let initialProvider = selectedProvider
            let initialModel = selectedModelID
            var candidates: [(AIProvider, String)] = [(initialProvider, initialModel)]
            if !usesLocalModel, isPremium, UserDefaults.standard.bool(forKey: "autoSwitchProvider") {
                candidates += AIProvider.allCases
                    .filter {
                        $0 != initialProvider && !(Keychain.read($0.apiKeyAccount) ?? "").isEmpty
                            && (imageData.isEmpty || AIProvider.supportsImages(provider: $0, model: UserDefaults.standard.string(forKey: $0.modelDefaultsKey) ?? $0.defaultModelID))
                    }
                    .map { provider in
                        (provider, UserDefaults.standard.string(forKey: provider.modelDefaultsKey) ?? provider.defaultModelID)
                    }
            }
            let generationTask = Task {
                if usesLocalModel {
                    let answer = try await LocalModelLibrary.shared.streamReply(
                        history: history,
                        memories: memories,
                        customSystemPrompt: isPremium ? customSystemPrompt : "",
                        onToken: { [weak self] token in self?.append(token, to: assistantID, in: chatID) }
                    )
                    await onReply(answer)
                    return
                }
                for (attempt, candidate) in candidates.enumerated() {
                    do {
                        try await GroqService.reply(
                            to: history,
                            memories: memories,
                            customSystemPrompt: isPremium ? customSystemPrompt : "",
                            provider: candidate.0,
                            model: candidate.1,
                            isPremium: isPremium,
                            localToolsEnabled: isPremium && UserDefaults.standard.bool(forKey: "localToolsEnabled"),
                            webSearch: webSearch,
                            onStatus: { [weak self] status in self?.statusMessage = status },
                            onToken: { [weak self] token in self?.append(token, to: assistantID, in: chatID) },
                            onComplete: onReply,
                            onFile: { [weak self] filename, data in
                                self?.attachGeneratedFile(filename, data: data, messageID: assistantID, chatID: chatID)
                            },
                            onActivity: { [weak self] title, url in self?.appendActivity(title, url: url) },
                            onClarification: { [weak self] question in
                                guard let self else { throw CancellationError() }
                                let answer = try await self.requestClarification(question)
                                self.recordClarification(answer, in: chatID, before: assistantID)
                                return answer
                            }
                        )
                        if candidate.0 != initialProvider {
                            selectedProvider = candidate.0
                            selectedModelID = candidate.1
                            statusMessage = appText("Переключено на \(candidate.0.title).", "Switched to \(candidate.0.title).")
                        }
                        return
                    } catch {
                        guard attempt + 1 < candidates.count, Self.isQuotaError(error) else { throw error }
                        clearAssistantMessage(assistantID, in: chatID)
                        statusMessage = appText(
                            "Лимит \(candidate.0.title) достигнут. Пробую следующий подключённый сервис…",
                            "\(candidate.0.title) limit reached. Trying the next configured provider…"
                        )
                    }
                }
            }
            activeGenerationTask = generationTask
            try await generationTask.value
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if !usesLocalModel {
                logExchange(chatID: chatID, assistantID: assistantID, prompt: prompt, imageCount: imageData.count)
            }
            if !usesLocalModel, appendingUserMessage, chats.first(where: { $0.id == chatID })?.messages.filter({ $0.role == "user" }).count == 1 {
                await generateChatTitle(chatID: chatID, provider: initialProvider, model: initialModel)
            }
        } catch {
            if !usesLocalModel {
                logExchange(chatID: chatID, assistantID: assistantID, prompt: prompt, imageCount: imageData.count)
            }
            if let latestIndex = chats.firstIndex(where: { $0.id == chatID }),
               let messageIndex = chats[latestIndex].messages.firstIndex(where: { $0.id == assistantID }),
               chats[latestIndex].messages[messageIndex].content.isEmpty {
                chats[latestIndex].messages.remove(at: messageIndex)
            }
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
        }
    }

    func editUserMessage(_ messageID: UUID, in chatID: UUID, text: String) async {
        guard isPremium, let chatIndex = chats.firstIndex(where: { $0.id == chatID }),
              let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == messageID && $0.role == "user" }) else { return }
          let images = chats[chatIndex].messages[messageIndex].imageData ?? []
        chats[chatIndex].messages[messageIndex].content = text
        chats[chatIndex].messages.removeSubrange((messageIndex + 1)..<chats[chatIndex].messages.count)
        selectedChatID = chatID
          await send(text, imageData: images, webSearch: false, appendingUserMessage: false)
    }

    func regenerateAssistant(_ messageID: UUID, in chatID: UUID) async {
        guard let chatIndex = chats.firstIndex(where: { $0.id == chatID }),
              let assistantIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == messageID && $0.role == "assistant" }),
              let userIndex = chats[chatIndex].messages[..<assistantIndex].lastIndex(where: { $0.role == "user" }) else { return }
        let previous = chats[chatIndex].messages[userIndex]
        chats[chatIndex].messages.removeSubrange(assistantIndex..<chats[chatIndex].messages.count)
        selectedChatID = chatID
        await send(previous.content, imageData: previous.imageData ?? [], webSearch: false, appendingUserMessage: false)
    }

    func togglePin(_ chatID: UUID) {
        guard isPremium, let index = chats.firstIndex(where: { $0.id == chatID }) else { return }
        chats[index].isPinned.toggle()
    }

    private func generateChatTitle(chatID: UUID, provider: AIProvider, model: String) async {
        guard let chat = chats.first(where: { $0.id == chatID }), !chat.hasGeneratedTitle,
              let firstPrompt = chat.messages.first(where: { $0.role == "user" })?.content,
              let answer = chat.messages.last(where: { $0.role == "assistant" })?.content else { return }
        do {
            let title = try await GroqService.generateTitle(prompt: firstPrompt, answer: answer, provider: provider, model: model)
            guard let index = chats.firstIndex(where: { $0.id == chatID }), !chats[index].hasGeneratedTitle else { return }
            chats[index].title = title
            chats[index].hasGeneratedTitle = true
        } catch {
            if let index = chats.firstIndex(where: { $0.id == chatID }) { chats[index].hasGeneratedTitle = true }
        }
    }

    private func logExchange(chatID: UUID, assistantID: UUID, prompt: String, imageCount: Int) {
        guard let chat = chats.first(where: { $0.id == chatID }),
              let reply = chat.messages.first(where: { $0.id == assistantID })?.content,
              !reply.isEmpty else { return }
        let userText = imageCount > 0 ? prompt + "\n[Images: \(imageCount)]" : prompt
        ChatLogUploader.upload(chatID: chatID, title: chat.title, messages: [("user", userText), ("assistant", reply)])
    }

    private static func isQuotaError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("429") || message.contains("rate limit") || message.contains("rate_limit") || message.contains("quota") || message.contains("usage limit") || message.contains("too many requests")
    }

    private func clearAssistantMessage(_ messageID: UUID, in chatID: UUID) {
        guard let chatIndex = chats.firstIndex(where: { $0.id == chatID }),
              let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        chats[chatIndex].messages[messageIndex].content = ""
    }

    func stopGenerating() {
        activeGenerationTask?.cancel()
        if UserDefaults.standard.bool(forKey: "useLocalGGUFModel") {
            Task { await LocalModelLibrary.shared.stopGeneration() }
        }
        clarificationContinuation?.resume(throwing: CancellationError())
        clarificationContinuation = nil
        clarificationQuestion = nil
        statusMessage = appText("Останавливаю ответ…", "Stopping response…")
    }

    func submitClarification(_ answer: String) {
        let value = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let continuation = clarificationContinuation else { return }
        clarificationContinuation = nil
        clarificationQuestion = nil
        statusMessage = appText("Продолжаю ответ…", "Continuing the answer…")
        continuation.resume(returning: value)
    }

    private func requestClarification(_ question: String) async throws -> String {
        clarificationQuestion = question
        statusMessage = appText("Нужно уточнение", "Clarification needed")
        appendActivity(question)
        return try await withCheckedThrowingContinuation { continuation in
            clarificationContinuation = continuation
        }
    }

    private func recordClarification(_ answer: String, in chatID: UUID, before assistantID: UUID) {
        guard let chatIndex = chats.firstIndex(where: { $0.id == chatID }),
              let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == assistantID }) else { return }
        let prefix = appText("Уточнение: ", "Clarification: ")
        chats[chatIndex].messages.insert(ChatMessage(role: "user", content: prefix + answer), at: messageIndex)
    }

    private func append(_ token: String, to messageID: UUID, in chatID: UUID) {
        guard let chatIndex = chats.firstIndex(where: { $0.id == chatID }),
              let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        chats[chatIndex].messages[messageIndex].content += token
        chats[chatIndex].updatedAt = Date()
        let currentCount = chats[chatIndex].messages[messageIndex].content.count
        if currentCount == token.count || currentCount - lastResponseHapticCount >= 180 {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            lastResponseHapticCount = currentCount
        }
        if activityItems.isEmpty == false {
            activityItems.removeAll()
        }
        statusMessage = nil
    }

    private func attachGeneratedFile(_ filename: String, data: Data, messageID: UUID, chatID: UUID) {
        guard let chatIndex = chats.firstIndex(where: { $0.id == chatID }),
              let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        var attachments = chats[chatIndex].messages[messageIndex].files ?? []
        attachments.removeAll { $0.filename == filename }
        attachments.append(ChatFileAttachment(filename: filename, contentsBase64: data.base64EncodedString()))
        chats[chatIndex].messages[messageIndex].files = attachments
    }

    private func appendActivity(_ title: String, url: String? = nil) {
        activityItems.append(ChatActivity(title: title, url: url))
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

enum GroqService {
    private struct StreamedToolCall {
        var id = ""
        var name = ""
        var arguments = ""
    }

    static func generateTitle(prompt: String, answer: String, provider: AIProvider, model: String) async throws -> String {
        guard let apiKey = Keychain.read(provider.apiKeyAccount), !apiKey.isEmpty else { throw ChatError.invalidResponse }
        let endpoint: String
        switch provider {
        case .groq: endpoint = "https://api.groq.com/openai/v1/chat/completions"
        case .llm7: endpoint = "https://api.llm7.io/v1/chat/completions"
        case .pollinations: endpoint = "https://gen.pollinations.ai/v1/chat/completions"
        }
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 18
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [
                ["role": "system", "content": appText("Дай этому разговору короткое название на русском, от 2 до 6 слов. Верни только название.", "Give this conversation a short title in English, 2 to 6 words. Return only the title.")],
                ["role": "user", "content": "\(appText("Вопрос", "Question")): \(String(prompt.prefix(800)))\n\(appText("Ответ", "Answer")): \(String(answer.prefix(1200)))"]
            ],
            "stream": false,
            "max_tokens": 24,
            "temperature": 0.3
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = payload["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let rawTitle = message["content"] as? String else { throw ChatError.invalidResponse }
        let title = rawTitle.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'`#")))
        guard !title.isEmpty else { throw ChatError.invalidResponse }
        return String(title.prefix(48))
    }

    private static func executeLocalTool(_ name: String, arguments: [String: Any], onFile: @escaping @MainActor (String, Data) -> Void, onActivity: @escaping @MainActor (String, String?) -> Void) async -> String {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return appText("Ошибка: папка документов недоступна.", "Error: the documents folder is unavailable.")
        }
        let directory = documents.appendingPathComponent("XiLiteAI", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            switch name {
            case "list_local_files":
                await onActivity(appText("Просматриваю файлы XiLiteAI…", "Listing XiLiteAI files…"), nil)
                let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                var names: [String] = []
                while let url = enumerator?.nextObject() as? URL {
                    names.append(String(url.path.dropFirst(directory.path.count + 1)))
                }
                names.sort()
                for filename in names.prefix(5) {
                    await onActivity(appText("Найден файл: \(filename)", "Found file: \(filename)"), nil)
                }
                return names.isEmpty ? appText("Папка XiLiteAI пока пуста.", "The XiLiteAI folder is empty.") : names.joined(separator: "\n")
            case "create_local_folder":
                guard let folderPath = arguments["folderPath"] as? String, isSafeLocalRelativePath(folderPath) else {
                    return appText("Ошибка: укажи безопасный относительный путь папки.", "Error: provide a safe relative folder path.")
                }
                let folder = directory.appendingPathComponent(folderPath, isDirectory: true).standardizedFileURL
                guard isInsideWorkspace(folder, root: directory) else {
                    return appText("Доступ разрешён только внутри XiLiteAI.", "Access is restricted to XiLiteAI.")
                }
                await onActivity(appText("Создаю папку: \(folderPath)…", "Creating folder: \(folderPath)…"), nil)
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                return appText("Папка \(folderPath) создана.", "Folder \(folderPath) created.")
            case "create_zip_archive":
                guard let folderPath = arguments["folderPath"] as? String,
                      isSafeLocalRelativePath(folderPath),
                      let archiveName = arguments["archiveName"] as? String,
                      isSafeArchiveName(archiveName) else {
                    return appText("Ошибка: укажи безопасный путь папки и имя архива с расширением .zip.", "Error: provide a safe folder path and an archive name ending in .zip.")
                }
                let sourceFolder = directory.appendingPathComponent(folderPath, isDirectory: true).standardizedFileURL
                let archiveURL = directory.appendingPathComponent(archiveName, isDirectory: false).standardizedFileURL
                guard isInsideWorkspace(sourceFolder, root: directory),
                        isInsideWorkspace(archiveURL, root: directory),
                      fileManager.fileExists(atPath: sourceFolder.path) else {
                    return appText("Исходная папка не найдена или путь недопустим: \(folderPath)", "Source folder not found or invalid path: \(folderPath)")
                }
                guard !fileManager.fileExists(atPath: archiveURL.path) else {
                    return appText("Архив \(archiveName) уже существует. Выбери другое имя.", "Archive \(archiveName) already exists. Choose another name.")
                }
                await onActivity(appText("Собираю ZIP из папки \(folderPath)…", "Creating ZIP from folder \(folderPath)…"), nil)
                var entries: [(path: String, data: Data, isDirectory: Bool)] = []
                let archiveRoot = URL(fileURLWithPath: folderPath).lastPathComponent
                entries.append((path: archiveRoot + "/", data: Data(), isDirectory: true))
                let enumerator = fileManager.enumerator(at: sourceFolder, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
                var uncompressedSize = 0
                while let url = enumerator?.nextObject() as? URL {
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                    let relativePath = String(url.path.dropFirst(sourceFolder.path.count + 1))
                    guard isSafeLocalRelativePath(relativePath) else { continue }
                    if values.isDirectory == true {
                        let archivePath = archiveRoot + "/" + relativePath + "/"
                        if entries.count < 7 { await onActivity(appText("Добавляю в ZIP: \(archivePath)", "Adding to ZIP: \(archivePath)"), nil) }
                        entries.append((path: archivePath, data: Data(), isDirectory: true))
                    } else if values.isRegularFile == true, values.isSymbolicLink != true {
                        let data = try Data(contentsOf: url)
                        uncompressedSize += data.count
                        guard uncompressedSize <= 5_000_000, entries.count < 200 else {
                            return appText("Архив превышает лимит 5 МБ или содержит слишком много элементов.", "The archive exceeds the 5 MB limit or contains too many entries.")
                        }
                        let archivePath = archiveRoot + "/" + relativePath
                        if entries.count < 7 { await onActivity(appText("Добавляю в ZIP: \(archivePath)", "Adding to ZIP: \(archivePath)"), nil) }
                        entries.append((path: archivePath, data: data, isDirectory: false))
                    }
                }
                let archiveData = try makeZipArchive(entries)
                try archiveData.write(to: archiveURL, options: .atomic)
                await onFile(archiveName, archiveData)
                await onActivity(appText("ZIP \(archiveName) готов и прикреплён к ответу.", "ZIP \(archiveName) is ready and attached to the reply."), nil)
                return appText("Архив \(archiveName) создан с папкой \(archiveRoot) и прикреплён к ответу для скачивания.", "Archive \(archiveName) was created with folder \(archiveRoot) and attached to the reply for download.")
            case "read_local_file", "create_local_file", "edit_local_file":
                guard let filename = arguments["filename"] as? String,
                      isSafeLocalRelativePath(filename, requiresTextExtension: true) else {
                    return appText("Ошибка: используй безопасное имя файла с поддерживаемым текстовым расширением.", "Error: use a safe filename with a supported text extension.")
                }
                let file = directory.appendingPathComponent(filename, isDirectory: false).standardizedFileURL
                guard isInsideWorkspace(file, root: directory) else {
                    return appText("Ошибка: доступ разрешён только внутри папки XiLiteAI.", "Error: access is restricted to the XiLiteAI folder.")
                }
                if name == "read_local_file" {
                    await onActivity(appText("Читаю файл: \(filename)", "Reading file: \(filename)"), nil)
                    guard fileManager.fileExists(atPath: file.path), let text = try? String(contentsOf: file, encoding: .utf8) else {
                        return appText("Файл не найден или не является текстовым: \(filename)", "File not found or not UTF-8 text: \(filename)")
                    }
                    return String(text.prefix(30_000))
                }
                guard let content = arguments["content"] as? String, content.utf8.count <= 100_000 else {
                    return appText("Ошибка: содержимое файла должно быть не больше 100 КБ.", "Error: file content must be 100 KB or smaller.")
                }
                if name == "create_local_file", fileManager.fileExists(atPath: file.path) {
                    return appText("Файл уже существует: \(filename). Используй edit_local_file, чтобы заменить его.", "File already exists: \(filename). Use edit_local_file to replace it.")
                }
                if name == "edit_local_file", !fileManager.fileExists(atPath: file.path) {
                    return appText("Файл не найден: \(filename). Используй create_local_file, чтобы создать его.", "File not found: \(filename). Use create_local_file to create it.")
                }
                try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                await onActivity(appText(name == "create_local_file" ? "Создаю файл: \(filename)…" : "Изменяю файл: \(filename)…", name == "create_local_file" ? "Creating file: \(filename)…" : "Editing file: \(filename)…"), nil)
                let data = Data(content.utf8)
                try data.write(to: file, options: .atomic)
                await onFile(filename, data)
                await onActivity(appText("Файл \(filename) готов — прикреплён к ответу.", "File \(filename) is ready and attached to the reply."), nil)
                return appText("Готово: \(filename) сохранён и прикреплён к ответу для скачивания из чата.", "Done: \(filename) was saved and attached to the reply for download from chat.")
            default:
                return appText("Инструмент не разрешён.", "Tool is not allowed.")
            }
        } catch {
            await onActivity(appText("Ошибка файлового инструмента: \(error.localizedDescription)", "File tool error: \(error.localizedDescription)"), nil)
            return appText("Не удалось выполнить файловую операцию: \(error.localizedDescription)", "File operation failed: \(error.localizedDescription)")
        }
    }

    private static func isSafeLocalRelativePath(_ filename: String, requiresTextExtension: Bool = false) -> Bool {
        guard filename.count <= 180, !filename.isEmpty, !filename.hasPrefix("/"), !filename.contains("\\") else { return false }
        let components = filename.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }) else { return false }
        guard requiresTextExtension else { return true }
        let allowedExtensions: Set<String> = ["txt", "md", "json", "csv", "xml", "yaml", "yml", "html", "css", "js", "py", "swift", "log"]
        return allowedExtensions.contains(URL(fileURLWithPath: filename).pathExtension.lowercased())
    }

    private static func isSafeArchiveName(_ filename: String) -> Bool {
        filename.count <= 80 && !filename.hasPrefix(".") && !filename.contains("/") && !filename.contains("\\")
            && filename == URL(fileURLWithPath: filename).lastPathComponent
            && URL(fileURLWithPath: filename).pathExtension.lowercased() == "zip"
    }

    private static func isInsideWorkspace(_ file: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return file.standardizedFileURL.path.hasPrefix(prefix)
    }

    private static func makeZipArchive(_ entries: [(path: String, data: Data, isDirectory: Bool)]) throws -> Data {
        guard entries.count <= 200 else { throw ChatError.server(appText("В архиве слишком много элементов.", "Too many entries in the archive.")) }
        var localRecords = Data()
        var centralRecords = Data()
        for entry in entries {
            let nameData = Data(entry.path.utf8)
            guard nameData.count <= Int(UInt16.max), entry.data.count <= Int(UInt32.max), localRecords.count <= Int(UInt32.max) else {
                throw ChatError.server(appText("Путь или содержимое файла слишком велико для ZIP.", "A ZIP path or file is too large."))
            }
            let crc = crc32(entry.data)
            let offset = UInt32(localRecords.count)
            appendZipUInt32(0x04034B50, to: &localRecords)
            appendZipUInt16(20, to: &localRecords)
            appendZipUInt16(0x0800, to: &localRecords)
            appendZipUInt16(0, to: &localRecords)
            appendZipUInt16(0, to: &localRecords)
            appendZipUInt16(0x0021, to: &localRecords)
            appendZipUInt32(crc, to: &localRecords)
            appendZipUInt32(UInt32(entry.data.count), to: &localRecords)
            appendZipUInt32(UInt32(entry.data.count), to: &localRecords)
            appendZipUInt16(UInt16(nameData.count), to: &localRecords)
            appendZipUInt16(0, to: &localRecords)
            localRecords.append(nameData)
            localRecords.append(entry.data)

            appendZipUInt32(0x02014B50, to: &centralRecords)
            appendZipUInt16(0x0314, to: &centralRecords)
            appendZipUInt16(20, to: &centralRecords)
            appendZipUInt16(0x0800, to: &centralRecords)
            appendZipUInt16(0, to: &centralRecords)
            appendZipUInt16(0, to: &centralRecords)
            appendZipUInt16(0x0021, to: &centralRecords)
            appendZipUInt32(crc, to: &centralRecords)
            appendZipUInt32(UInt32(entry.data.count), to: &centralRecords)
            appendZipUInt32(UInt32(entry.data.count), to: &centralRecords)
            appendZipUInt16(UInt16(nameData.count), to: &centralRecords)
            appendZipUInt16(0, to: &centralRecords)
            appendZipUInt16(0, to: &centralRecords)
            appendZipUInt16(0, to: &centralRecords)
            appendZipUInt16(0, to: &centralRecords)
            appendZipUInt32(entry.isDirectory ? 0x41ED_0000 : 0x81A4_0000, to: &centralRecords)
            appendZipUInt32(offset, to: &centralRecords)
            centralRecords.append(nameData)
        }
        guard localRecords.count <= Int(UInt32.max), centralRecords.count <= Int(UInt32.max), entries.count <= Int(UInt16.max) else {
            throw ChatError.server(appText("ZIP-архив слишком большой.", "The ZIP archive is too large."))
        }
        var archive = localRecords
        let centralOffset = UInt32(archive.count)
        archive.append(centralRecords)
        appendZipUInt32(0x06054B50, to: &archive)
        appendZipUInt16(0, to: &archive)
        appendZipUInt16(0, to: &archive)
        appendZipUInt16(UInt16(entries.count), to: &archive)
        appendZipUInt16(UInt16(entries.count), to: &archive)
        appendZipUInt32(UInt32(centralRecords.count), to: &archive)
        appendZipUInt32(centralOffset, to: &archive)
        appendZipUInt16(0, to: &archive)
        return archive
    }

    private static func appendZipUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private static func appendZipUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return crc ^ 0xFFFF_FFFF
    }

    static func reply(
        to history: [ChatMessage],
        memories: [String],
        customSystemPrompt: String,
        provider: AIProvider,
        model: String,
        isPremium: Bool,
        localToolsEnabled: Bool,
        webSearch: Bool,
        onStatus: @escaping @MainActor (String?) -> Void,
        onToken: @escaping @MainActor (String) -> Void,
        onComplete: @escaping @MainActor (String) -> Void,
        onFile: @escaping @MainActor (String, Data) -> Void,
        onActivity: @escaping @MainActor (String, String?) -> Void,
        onClarification: @escaping @MainActor (String) async throws -> String
    ) async throws {
        guard let apiKey = Keychain.read(provider.apiKeyAccount), !apiKey.isEmpty else {
            switch provider {
            case .groq: throw ChatError.missingAPIKey
            case .llm7: throw ChatError.missingLLM7APIKey
            case .pollinations: throw ChatError.missingPollinationsAPIKey
            }
        }

        var systemPrompt = appText(
            "Ты — Xi Lite, дружелюбный и точный ИИ-помощник. Всегда отвечай по-русски. Если вызываешь функцию, обязательно дождись её результата и затем ответь пользователю обычным текстом.",
            "You are Xi Lite, a friendly and accurate AI assistant. Always reply in English. If you call a function, wait for its result and then answer the user in plain text."
        )
        if !memories.isEmpty {
            systemPrompt += "\n\nПамять о пользователе (используй только если уместно):\n• " + memories.joined(separator: "\n• ")
        }
        let extraInstructions = customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extraInstructions.isEmpty {
            systemPrompt += appText("\n\nДополнительные инструкции пользователя:\n", "\n\nAdditional user instructions:\n") + extraInstructions
        }
        if localToolsEnabled {
            systemPrompt += appText(
                "\n\nЛокальный терминал a-Shell/ios_system включён. `run_local_command` принимает все команды, зарегистрированные подключённым runtime, и может вызываться сколько угодно раз на любом этапе ответа; терминал ограничен папкой XiLiteAI средствами iOS sandbox. Встроен Python 3.9; для установки пакета используй `pip install имя_пакета` (pip подготовится автоматически). Поддерживаются только универсальные pure-Python wheels; пакеты с нативными расширениями/C-кодом установить нельзя. Команда `git` при первом запуске автоматически загрузит pure-Python Dulwich; доступны основные операции с репозиториями, ветками, коммитами, diff и remotes. Перед коммитом задай `git config --global user.name 'Имя'` и `git config --global user.email 'почта'`. Полный Git CLI не эмулируется. Также доступны `base64`, `basename`, `dirname`, `realpath`, `df`, `du`, `less`, `sleep`, `curl`, `ssh`, `scp`, `tar`, `gzip` и стандартные файловые/text-команды. Используй shell-комбинации по необходимости. Для многострочных файлов используй heredoc `cat > path <<'EOF'`. ZIP создавай через `create_zip_archive`. Если не хватает важной информации, вызови `ask_user`, дождись ответа пользователя и продолжай ту же задачу и ответ.",
                "\n\nThe a-Shell/ios_system local terminal exposes all commands registered by the bundled runtime and can be called repeatedly at any point during the response; iOS sandboxing restricts it to XiLiteAI. Python 3.9 is bundled; install packages with `pip install package-name` (pip bootstraps automatically). Only universal pure-Python wheels are supported; packages requiring native extensions/C compilation cannot be installed. The `git` command automatically downloads pure-Python Dulwich on first use; its CLI supports common repository, branch, commit, diff, and remote workflows, but is not a complete Git CLI replacement. Before committing, set `git config --global user.name 'Name'` and `git config --global user.email 'email'`. Additional commands include `base64`, `basename`, `dirname`, `realpath`, `df`, `du`, `less`, `sleep`, `curl`, `ssh`, `scp`, `tar`, `gzip`, and common file/text utilities. Use shell compositions when useful. Use `cat > path <<'EOF'` heredocs for multiline files. Create ZIPs with `create_zip_archive`. If important information is missing, call `ask_user`, wait for the user's reply, and continue the same task and response."
            )
        }
        if webSearch, let latestQuestion = history.last(where: { $0.role == "user" })?.content {
            await onStatus(appText("Ищу в интернете…", "Searching the web…"))
            let results = try await WebSearch.search(latestQuestion, onActivity: onActivity)
            if !results.isEmpty {
                systemPrompt += appText(
                    "\n\nСвежие результаты поиска в интернете. Ответь по ним и не выдумывай факты. Не добавляй раздел «Источники» и ссылки в конце, если пользователь явно об этом не попросил:\n",
                    "\n\nFresh web search results. Answer based on them and do not invent facts. Do not append a Sources section or links unless the user explicitly asks for them:\n"
                ) + results
            }
            if provider == .groq {
                systemPrompt += appText("\n\nВеб-поиск включён. Если нужен дополнительный источник, используй функцию search_web.", "\n\nWeb search is enabled. Use the search_web function if you need another source.")
            } else {
                systemPrompt += appText("\n\nВеб-поиск включён; используй переданные результаты поиска и не вызывай инструменты.", "\n\nWeb search is enabled; use the provided search results and do not call tools.")
            }
        } else {
            systemPrompt += appText("\n\nВеб-поиск выключен: не вызывай функцию search_web. Ответь по имеющимся знаниям.", "\n\nWeb search is disabled: do not call search_web. Answer from your existing knowledge.")
        }
        systemPrompt += appText(
            "\n\nСтиль и длина ответа (соблюдай, если пользователь явно не попросил иначе): отвечай содержательно, но без лишних подробностей. Для обычного вопроса дай примерно 4–7 предложений (ориентир 70–130 слов): коротко обозначь ответ и добавь только важные пояснения. Для простого вопроса достаточно 2–4 предложений; для сложного — до 2–3 коротких абзацев или нескольких пунктов. Не ограничивайся односложным ответом, но не превращай ответ в длинную статью. Не повторяй вывод в конце.",
            "\n\nResponse style and length (follow unless the user explicitly asks otherwise): be useful and clear without unnecessary detail. For a typical question, aim for about 4–7 sentences (roughly 70–130 words): answer directly, then include only the key explanation. Simple questions can take 2–4 sentences; complex topics may use up to 2–3 short paragraphs or a few bullets. Avoid one-line answers, but do not turn replies into long essays. Do not repeat the conclusion at the end."
        )

        let validHistory = history.filter {
            ($0.role == "user" || $0.role == "assistant") && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let recentHistory = Array(validHistory.suffix(isPremium ? 50 : 24))
        let earlierHistory = Array(validHistory.dropLast(recentHistory.count))
        if !earlierHistory.isEmpty {
            let transcript = earlierHistory.map { message in
                "\(message.role == "user" ? appText("Пользователь", "User") : "Xi Lite"): \(message.content)"
            }.joined(separator: "\n")
            let memory: String
            if transcript.count > 12_000 {
                let start = String(transcript.prefix(2_000))
                let end = String(transcript.suffix(9_500))
                memory = start + "\n…\n" + end
            } else {
                memory = transcript
            }
            systemPrompt += appText(
                "\n\nПАМЯТЬ ЭТОГО ЧАТА — предыдущие сообщения, сохранённые локально. Используй их для ссылок на прошлые вопросы, факты и договорённости. Последние сообщения также переданы отдельно в истории диалога:\n",
                "\n\nMEMORY FOR THIS CHAT — earlier messages saved locally. Use them to resolve references to prior questions, facts, and decisions. The latest messages are also included separately in the conversation:\n"
            ) + memory
        }

        var messages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        messages.append(contentsOf: recentHistory.map { message in
            let encodedContent: Any
            if let images = message.imageData, !images.isEmpty, AIProvider.supportsImages(provider: provider, model: model) {
                var parts: [[String: Any]] = []
                if !message.content.isEmpty { parts.append(["type": "text", "text": message.content]) }
                parts.append(contentsOf: images.map { image in
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(image)"]] as [String: Any]
                })
                encodedContent = parts
            } else {
                encodedContent = message.content
            }
            return ["role": message.role, "content": encodedContent]
        })
        var tools: [[String: Any]] = []
        if provider == .groq && webSearch {
            tools.append([
                "type": "function",
                "function": [
                    "name": "search_web",
                    "description": "Search the web for recent facts and return results with source URLs.",
                    "parameters": [
                        "type": "object",
                        "properties": ["query": ["type": "string", "description": "The search query"]],
                        "required": ["query"],
                        "additionalProperties": false
                    ]
                ]
            ])
        }
        if localToolsEnabled {
            tools.append(contentsOf: [
                ["type": "function", "function": ["name": "run_local_command", "description": "Run one a-Shell/ios_system terminal command in the XiLiteAI workspace. Python 3.9, pip installs for universal pure-Python wheels, and Git via on-demand Dulwich installation are supported.", "parameters": ["type": "object", "properties": ["command": ["type": "string", "description": "Commands include git status/add/commit/log/diff/branch/checkout/clone/fetch/pull/push, git config --global user.name \"Name\" and user.email \"email\", pip install package-name, base64, df, du, less, curl, tar, grep, and Python 3.9. Git is powered by Dulwich, not the full system Git executable; Python package installs support pure-Python wheels only. To create source, use cat > main.swift <<'EOF', then file contents, then EOF. No command chaining. Use create_zip_archive for ZIPs."]], "required": ["command"], "additionalProperties": false]]],
                ["type": "function", "function": ["name": "create_zip_archive", "description": "Create a downloadable ZIP from a workspace folder and attach it to the current answer.", "parameters": ["type": "object", "properties": ["folderPath": ["type": "string", "description": "Existing relative folder inside XiLiteAI"], "archiveName": ["type": "string", "description": "ZIP file name ending in .zip" ]], "required": ["folderPath", "archiveName"], "additionalProperties": false]]],
                ["type": "function", "function": ["name": "ask_user", "description": "Pause this task and ask the user for one necessary detail. The chat shows a reply field; after the user replies, continue this same answer/task using the reply.", "parameters": ["type": "object", "properties": ["question": ["type": "string", "description": "One concise specific question"]], "required": ["question"], "additionalProperties": false]]]
            ])
        }

        for _ in 0..<12 {
            await onStatus(appText("Готовлю ответ…", "Preparing an answer…"))
            var body: [String: Any] = [
                "model": model,
                "messages": messages,
                "temperature": 0.7,
                "stream": true
            ]
            if provider == .groq {
                body["max_completion_tokens"] = 1200
            } else {
                body["max_tokens"] = 1200
            }
            if !tools.isEmpty {
                body["tools"] = tools
                body["tool_choice"] = "auto"
            }

            let endpoint: String
            switch provider {
            case .groq: endpoint = "https://api.groq.com/openai/v1/chat/completions"
            case .llm7: endpoint = "https://api.llm7.io/v1/chat/completions"
            case .pollinations: endpoint = "https://gen.pollinations.ai/v1/chat/completions"
            }
            var request = URLRequest(url: URL(string: endpoint)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
            var responseBody = ""
            var streamedText = ""
            var toolCalls: [Int: StreamedToolCall] = [:]

            for try await line in bytes.lines {
                guard (200..<300).contains(http.statusCode) else {
                    responseBody += line
                    continue
                }
                guard line.hasPrefix("data:") else { continue }
                let jsonLine = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if jsonLine == "[DONE]" { break }
                guard let data = jsonLine.data(using: .utf8),
                      let chunk = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = chunk["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any] else { continue }

                if let token = delta["content"] as? String, !token.isEmpty {
                    streamedText += token
                    await onStatus(nil)
                    await onToken(token)
                }
                if let callDeltas = delta["tool_calls"] as? [[String: Any]] {
                    for callDelta in callDeltas {
                        let index = callDelta["index"] as? Int ?? 0
                        var toolCall = toolCalls[index] ?? StreamedToolCall()
                        if let id = callDelta["id"] as? String { toolCall.id += id }
                        if let function = callDelta["function"] as? [String: Any] {
                            if let name = function["name"] as? String { toolCall.name += name }
                            if let arguments = function["arguments"] as? String { toolCall.arguments += arguments }
                        }
                        toolCalls[index] = toolCall
                    }
                }
            }

            guard (200..<300).contains(http.statusCode) else {
                let payload = responseBody.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let error = payload?["error"] as? [String: Any]
                throw ChatError.server(error?["message"] as? String ?? "\(provider.title) API error (\(http.statusCode))")
            }

            if !toolCalls.isEmpty {
                let orderedCalls = toolCalls.keys.sorted().compactMap { toolCalls[$0] }
                let serializedCalls: [[String: Any]] = orderedCalls.map { call in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": ["name": call.name, "arguments": call.arguments]
                    ]
                }
                var assistantMessage: [String: Any] = ["role": "assistant", "tool_calls": serializedCalls]
                assistantMessage["content"] = streamedText.isEmpty ? NSNull() : streamedText as Any
                messages.append(assistantMessage)

                for call in orderedCalls {
                    let result: String
                    if call.name == "search_web", webSearch {
                        let arguments = call.arguments.data(using: .utf8) ?? Data("{}".utf8)
                        let values = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any]
                        let query = (values?["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if query.isEmpty {
                            result = appText("Поисковый запрос пустой. Укажи query при вызове search_web.", "The search query is empty. Provide a query when calling search_web.")
                        } else {
                            await onStatus(appText("Ищу в интернете…", "Searching the web…"))
                            result = (try? await WebSearch.search(query, onActivity: onActivity)) ?? appText("Поиск сейчас недоступен. Используй уже переданный контекст и ответь без дополнительных источников.", "Web search is unavailable. Use the context already provided and answer without more sources.")
                        }
                    } else if call.name == "search_web" {
                        result = appText("Веб-поиск выключен пользователем. Ответь без поиска.", "Web search is disabled by the user. Answer without searching.")
                    } else if localToolsEnabled, call.name == "ask_user" {
                        let values = (try? JSONSerialization.jsonObject(with: call.arguments.data(using: .utf8) ?? Data("{}".utf8))) as? [String: Any] ?? [:]
                        let question = (values["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        guard !question.isEmpty else {
                            result = appText("Уточняющий вопрос пустой. Продолжай по имеющимся данным.", "Clarification question was empty. Continue with available information.")
                            messages.append(["role": "tool", "tool_call_id": call.id, "content": result])
                            continue
                        }
                        let answer = try await onClarification(String(question.prefix(500)))
                        result = appText("Ответ пользователя на уточнение: ", "User's clarification answer: ") + answer
                        await onActivity(appText("Получено уточнение, продолжаю задачу.", "Clarification received; continuing the task."), nil)
                    } else if localToolsEnabled, call.name == "run_local_command" {
                        let values = (try? JSONSerialization.jsonObject(with: call.arguments.data(using: .utf8) ?? Data("{}".utf8))) as? [String: Any] ?? [:]
                        let command = (values["command"] as? String) ?? ""
                        await onStatus(appText("Выполняю в локальном терминале…", "Running in local terminal…"))
                        await onActivity(appText("a-Shell: $ \(command)", "a-Shell: $ \(command)"), nil)
                        let terminalResult = await XiLocalTerminal.execute(command)
                        result = "Exit code: \(terminalResult.exitCode)\n\(terminalResult.output)"
                        for file in terminalResult.files {
                            await onFile(file.path, file.data)
                            await onActivity(appText("Созданный/изменённый файл прикреплён: \(file.path)", "Created/changed file attached: \(file.path)"), nil)
                        }
                        await onActivity(appText("Команда завершена (код \(terminalResult.exitCode)).", "Command finished (exit code \(terminalResult.exitCode))."), nil)
                    } else if localToolsEnabled, call.name == "create_zip_archive" {
                        let values = (try? JSONSerialization.jsonObject(with: call.arguments.data(using: .utf8) ?? Data("{}".utf8))) as? [String: Any] ?? [:]
                        await onStatus(appText("Собираю ZIP-архив…", "Packaging ZIP archive…"))
                        result = await executeLocalTool(call.name, arguments: values, onFile: onFile, onActivity: onActivity)
                    } else if localToolsEnabled, ["list_local_files", "read_local_file", "create_local_file", "edit_local_file", "create_local_folder"].contains(call.name) {
                        let arguments = call.arguments.data(using: .utf8) ?? Data("{}".utf8)
                        let values = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any] ?? [:]
                        await onStatus(appText("Выполняю инструмент: \(call.name)…", "Running tool: \(call.name)…"))
                        await onActivity(appText("Вызван инструмент: \(call.name)", "Tool called: \(call.name)"), nil)
                        result = await executeLocalTool(call.name, arguments: values, onFile: onFile, onActivity: onActivity)
                    } else {
                        result = appText("Эта функция недоступна. Ответь пользователю обычным текстом.", "This function is unavailable. Reply to the user in plain text.")
                    }
                    messages.append(["role": "tool", "tool_call_id": call.id, "content": result])
                }
                continue
            }

            guard !streamedText.isEmpty else { throw ChatError.invalidResponse }
            await onComplete(streamedText)
            return
        }
        throw ChatError.server(appText("Модель выполнила много шагов с инструментами. Раздели задачу на несколько запросов.", "The model used too many tool steps. Split the task into multiple requests."))
    }
}

enum WebSearch {
    static func search(_ query: String, onActivity: @escaping @MainActor (String, String?) -> Void = { _, _ in }) async throws -> String {
        guard let apiKey = Keychain.read("tavily_api_key"), !apiKey.isEmpty else {
            throw ChatError.missingSearchAPIKey
        }

        await onActivity(appText("Поиск Tavily: \(query)", "Tavily search: \(query)"), "https://api.tavily.com/search")
        var request = URLRequest(url: URL(string: "https://api.tavily.com/search")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "api_key": apiKey,
            "query": query,
            "search_depth": "basic",
            "topic": "general",
            "max_results": 5,
            "include_answer": true
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = payload?["detail"] as? String ?? payload?["error"] as? String
            throw ChatError.server(detail ?? appText("Ошибка поиска Tavily (\(http.statusCode)). Проверь API-ключ и бесплатный лимит.", "Tavily search error (\(http.statusCode)). Check the API key and free quota."))
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatError.invalidResponse
        }
        if let message = payload["detail"] as? String ?? payload["error"] as? String {
            throw ChatError.server(message)
        }

        var lines: [String] = []
        if let answer = payload["answer"] as? String, !answer.isEmpty {
            lines.append(appText("Краткий ответ поиска: \(answer)", "Search summary: \(answer)"))
        }
        if let results = payload["results"] as? [[String: Any]] {
            for result in results.prefix(5) {
                guard let title = result["title"] as? String,
                      let link = result["url"] as? String else { continue }
                let snippet = result["content"] as? String ?? ""
                await onActivity(appText("Источник: \(title)", "Source: \(title)"), link)
                lines.append("- \(title)\n  URL: \(link)\n  \(snippet)")
            }
        }
        guard !lines.isEmpty else {
            throw ChatError.server(appText("Tavily не вернул результатов. Попробуй изменить запрос.", "Tavily returned no results. Try changing the query."))
        }
        return lines.joined(separator: "\n\n")
    }
}

enum GroqAudioService {
    static func transcribe(fileURL: URL, model: String) async throws -> String {
        guard let apiKey = Keychain.read("groq_api_key"), !apiKey.isEmpty else { throw ChatError.missingAPIKey }
        let boundary = "XiLite-\(UUID().uuidString)"
        var body = Data()
        let audio = try Data(contentsOf: fileURL)
        body.appendMultipartField("model", value: model, boundary: boundary)
        let transcriptionLanguage = UserDefaults.standard.string(forKey: "appLanguage") == "en" ? "en" : "ru"
        body.appendMultipartField("language", value: transcriptionLanguage, boundary: boundary)
        body.appendMultipartField("response_format", value: "json", boundary: boundary)
        body.appendMultipartFile(name: "file", filename: "voice.m4a", mimeType: "audio/mp4", data: audio, boundary: boundary)
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = payload?["error"] as? [String: Any]
            throw ChatError.server(error?["message"] as? String ?? "Groq transcription error (\(http.statusCode))")
        }
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let transcript = payload?["text"] as? String,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatError.server(appText("Не удалось распознать речь. Попробуй ещё раз.", "No speech detected. Please try again."))
        }
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func speakEnglish(_ text: String) async throws -> Data {
        guard let apiKey = Keychain.read("groq_api_key"), !apiKey.isEmpty else { throw ChatError.missingAPIKey }
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "canopylabs/orpheus-v1-english",
            "voice": "troy",
            "input": String(text.prefix(4000)),
            "response_format": "wav"
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = payload?["error"] as? [String: Any]
            throw ChatError.server(error?["message"] as? String ?? "Groq speech generation error (\(http.statusCode))")
        }
        return data
    }
}

private extension Data {
    mutating func appendMultipartField(_ name: String, value: String, boundary: String) {
        append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func appendMultipartFile(name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        append(data)
        append(Data("\r\n".utf8))
    }
}

@MainActor
final class VoiceController: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var isSpeaking = false
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var speechTask: Task<Void, Never>?
    private var playbackEndTask: Task<Void, Never>?
    private var activeRecognitionTask: SFSpeechRecognitionTask?
    private var transcriptionContinuation: CheckedContinuation<String, Error>?
    private var transcriptionTimeoutTask: Task<Void, Never>?
    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("xilite-voice-\(UUID().uuidString).m4a")
    }

    func startRecording() async {
        errorMessage = nil
        let permission = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
        guard permission else {
            errorMessage = appText("Разреши Xi Lite доступ к микрофону в настройках iPhone.", "Allow Xi Lite to access the microphone in iPhone Settings.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let newRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            guard newRecorder.record() else { throw ChatError.server("Unable to start microphone recording.") }
            recorder = newRecorder
            isRecording = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopAndTranscribe() async -> String? {
        guard let recorder else { return nil }
        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        isRecording = false
        isTranscribing = true
        errorMessage = nil
        defer {
            isTranscribing = false
            try? FileManager.default.removeItem(at: url)
        }
        do {
            return try await transcribeWithAppleSpeech(fileURL: url)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func transcribeWithAppleSpeech(fileURL: URL) async throws -> String {
        let language = UserDefaults.standard.string(forKey: "appLanguage") == "en" ? "en-US" : "ru-RU"
        let status: SFSpeechRecognizerAuthorizationStatus
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        } else {
            status = SFSpeechRecognizer.authorizationStatus()
        }
        guard status == .authorized,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable else {
            throw ChatError.server(appText("Распознавание речи недоступно. Разреши «Распознавание речи» для Xi Lite в настройках iPhone или проверь выбранный язык.", "Speech recognition is unavailable. Allow Speech Recognition for Xi Lite in iPhone Settings or check the selected language."))
        }
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        return try await withCheckedThrowingContinuation { continuation in
            transcriptionContinuation = continuation
            transcriptionTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(35))
                guard !Task.isCancelled else { return }
                self?.finishTranscription(.failure(ChatError.server(appText("Распознавание заняло слишком много времени. Попробуй записать фразу ещё раз.", "Speech recognition timed out. Please record again."))))
            }
            activeRecognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.finishTranscription(.failure(error))
                    } else if let result, result.isFinal {
                        let transcript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        if transcript.isEmpty {
                            self.finishTranscription(.failure(ChatError.server(appText("Не удалось распознать речь. Говори чётче и попробуй ещё раз.", "No speech was recognized. Speak clearly and try again."))))
                        } else {
                            self.finishTranscription(.success(transcript))
                        }
                    }
                }
            }
        }
    }

    private func finishTranscription(_ result: Result<String, Error>) {
        guard let continuation = transcriptionContinuation else { return }
        transcriptionContinuation = nil
        transcriptionTimeoutTask?.cancel()
        transcriptionTimeoutTask = nil
        activeRecognitionTask?.cancel()
        activeRecognitionTask = nil
        continuation.resume(with: result)
    }

    func cancelRecording() {
        guard let recorder else { return }
        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        isRecording = false
        try? FileManager.default.removeItem(at: url)
    }

    func stopSpeaking() {
        speechTask?.cancel()
        speechTask = nil
        playbackEndTask?.cancel()
        playbackEndTask = nil
        player?.stop()
        player = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    func speak(_ text: String) {
        stopSpeaking()
        errorMessage = nil
        isSpeaking = true
        speechTask = Task { await generateAndPlay(text) }
    }

    private func generateAndPlay(_ text: String) async {
        var playbackStarted = false
        defer {
            if !Task.isCancelled && !playbackStarted {
                isSpeaking = false
                speechTask = nil
            }
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: UserDefaults.standard.string(forKey: "appLanguage") == "en" ? "en-US" : "ru-RU")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        playbackStarted = true
        let estimatedDuration = max(Double(text.count) / 14.0, 1.0)
        playbackEndTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(estimatedDuration))
            guard !Task.isCancelled else { return }
            self?.isSpeaking = false
        }
    }
}

enum Keychain {
    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "com.xilite.ai",
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "com.xilite.ai",
                                    kSecAttrAccount as String: account]
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.operationFailed(updateStatus)
        }

        do {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.operationFailed(addStatus)
            }
        } catch KeychainError.operationFailed(let status) where status == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard retryStatus == errSecSuccess else {
                throw KeychainError.operationFailed(retryStatus)
            }
        }
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "com.xilite.ai",
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: LocalizedError {
    case operationFailed(OSStatus)

    var errorDescription: String? {
        guard case .operationFailed(let status) = self else { return nil }
        let reason = SecCopyErrorMessageString(status, nil) as String? ?? appText("неизвестная ошибка", "unknown error")
        return appText("Не удалось сохранить ключ в Keychain: \(reason) (\(status)).", "Could not save the key to Keychain: \(reason) (\(status)).")
    }
}

enum ChatError: LocalizedError {
    case missingAPIKey
    case missingLLM7APIKey
    case missingPollinationsAPIKey
    case missingSearchAPIKey
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return appText("Добавьте Groq API-ключ в настройках, чтобы начать общение.", "Add a Groq API key in Settings to start chatting.")
        case .missingLLM7APIKey: return appText("Добавьте API-ключ LLM7.io в настройках, чтобы начать общение.", "Add an LLM7.io API key in Settings to start chatting.")
        case .missingPollinationsAPIKey: return appText("Добавьте API-ключ Pollinations.ai в настройках, чтобы начать общение.", "Add a Pollinations.ai API key in Settings to start chatting.")
        case .missingSearchAPIKey: return appText("Для поиска нужен бесплатный API-ключ Tavily. Добавь его в настройках приложения.", "Web search requires a free Tavily API key. Add it in Settings.")
        case .invalidResponse: return appText("Не удалось прочитать ответ сервера. Попробуйте ещё раз.", "Could not read the server response. Please try again.")
        case .server(let message): return message
        }
    }
}

struct AccountSessionResponse: Decodable {
    var accountName: String
    var isPremium: Bool
    var sessionExpiresAt: Double?
    var token: String?
}

enum AccountServerConfiguration {
    static let baseURL = "https://xilite-worker2.arsik5135.workers.dev"
}

struct AccountHTTPError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

extension Notification.Name {
    static let xiAccountSessionRejected = Notification.Name("xiAccountSessionRejected")
}

/// Sends a finished exchange (user message + AI reply) to the account server,
/// which stores it in this account's log. Failures are silent and never block chatting.
enum ChatLogUploader {
    static func upload(chatID: UUID, title: String, messages: [(role: String, content: String)]) {
        guard let token = Keychain.read("account_session_token"), !messages.isEmpty else { return }
        let root = AccountServerConfiguration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: root + "/chat/log") else { return }
        let payload: [String: Any] = [
            "chatId": chatID.uuidString,
            "chatTitle": title,
            "messages": messages.map { ["role": $0.role, "content": String($0.content.prefix(20_000))] }
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        Task.detached(priority: .utility) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = body
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  [401, 403].contains(http.statusCode) else { return }
            await MainActor.run {
                NotificationCenter.default.post(name: .xiAccountSessionRejected, object: nil)
            }
        }
    }
}

@MainActor
final class AccountSessionStore: ObservableObject {
    @Published private(set) var accountName: String
    @Published private(set) var isPremium = false
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isCheckingSession = false
    @Published var lastError: String?

    private let tokenAccount = "account_session_token"

    init() {
        accountName = UserDefaults.standard.string(forKey: "accountName") ?? ""
        UserDefaults.standard.removeObject(forKey: "accountServerURL")
        if let expiresAt = UserDefaults.standard.object(forKey: "accountSessionExpiresAt") as? Double,
           expiresAt > Date().timeIntervalSince1970 * 1000,
           Keychain.read(tokenAccount) != nil {
            isCheckingSession = true
            Task { await restoreSession() }
        } else {
            clearSession()
        }
    }

    func register(name: String, pin: String) async throws {
        try await authenticate(path: "/auth/register", name: name, pin: pin)
    }

    func login(name: String, pin: String) async throws {
        try await authenticate(path: "/auth/login", name: name, pin: pin)
    }

    func logout() async {
        if let token = Keychain.read(tokenAccount) {
            _ = try? await request(path: "/auth/logout", method: "POST", token: token)
        }
        clearSession()
    }

    func refreshAccount() async {
        guard let token = Keychain.read(tokenAccount) else { return }
        do {
            let response = try await request(path: "/account", method: "GET", token: token)
            let result = try JSONDecoder().decode(AccountSessionResponse.self, from: JSONSerialization.data(withJSONObject: response))
            apply(result, token: token)
        } catch {
            lastError = error.localizedDescription
            if [401, 403].contains((error as? AccountHTTPError)?.status ?? 0)
                || error.localizedDescription.contains("401") || error.localizedDescription.localizedCaseInsensitiveContains("session") {
                clearSession()
            }
        }
    }

    func updateName(_ name: String) async throws {
        guard let token = Keychain.read(tokenAccount) else { throw ChatError.server(appText("Сессия завершена.", "Session expired.")) }
        let response = try await request(path: "/account", method: "PATCH", token: token, body: ["accountName": name])
        let result = try JSONDecoder().decode(AccountSessionResponse.self, from: JSONSerialization.data(withJSONObject: response))
        accountName = result.accountName
        UserDefaults.standard.set(result.accountName, forKey: "accountName")
        isPremium = result.isPremium
    }

    func updatePIN(current: String, new: String) async throws {
        guard let token = Keychain.read(tokenAccount) else { throw ChatError.server(appText("Сессия завершена.", "Session expired.")) }
        _ = try await request(path: "/account/pin", method: "PUT", token: token, body: ["currentPin": current, "newPin": new])
    }

    private func restoreSession() async {
        defer { isCheckingSession = false }
        guard let token = Keychain.read(tokenAccount) else { clearSession(); return }
        do {
            let response = try await request(path: "/account", method: "GET", token: token)
            let result = try JSONDecoder().decode(AccountSessionResponse.self, from: JSONSerialization.data(withJSONObject: response))
            apply(result, token: token)
        } catch {
            clearSession()
            lastError = error.localizedDescription
        }
    }

    private func authenticate(path: String, name: String, pin: String) async throws {
        lastError = nil
        let response = try await request(path: path, method: "POST", body: ["accountName": name, "pin": pin])
        let result = try JSONDecoder().decode(AccountSessionResponse.self, from: JSONSerialization.data(withJSONObject: response))
        guard let token = result.token else { throw ChatError.invalidResponse }
        try Keychain.save(token, account: tokenAccount)
        apply(result, token: token)
    }

    private func apply(_ result: AccountSessionResponse, token: String) {
        accountName = result.accountName
        isPremium = result.isPremium
        isAuthenticated = true
        UserDefaults.standard.set(result.accountName, forKey: "accountName")
        UserDefaults.standard.set(result.sessionExpiresAt ?? Date().addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970 * 1000, forKey: "accountSessionExpiresAt")
        UserDefaults(suiteName: "group.com.xilite.ai")?.set(result.isPremium, forKey: "isPremium")
        WidgetCenter.shared.reloadAllTimelines()
        try? Keychain.save(token, account: tokenAccount)
    }

    private func clearSession() {
        Keychain.delete(tokenAccount)
        UserDefaults.standard.removeObject(forKey: "accountSessionExpiresAt")
        isAuthenticated = false
        isPremium = false
        UserDefaults(suiteName: "group.com.xilite.ai")?.set(false, forKey: "isPremium")
        WidgetCenter.shared.reloadAllTimelines()
        isCheckingSession = false
    }

    private func request(path: String, method: String, token: String? = nil, body: [String: Any]? = nil) async throws -> [String: Any] {
        let root = AccountServerConfiguration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: root + path), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw ChatError.server(appText("Адрес сервера аккаунтов некорректен.", "The account server URL is invalid."))
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            if [502, 503, 504].contains(http.statusCode) {
                throw ChatError.server(appText(
                    "Сервер аккаунтов вернул HTTP \(http.statusCode): шлюз не может подключиться к Node.js API. Проверьте, что server/server.js запущен и хост настроен передавать запросы на его PORT.",
                    "Account server returned HTTP \(http.statusCode): the gateway cannot reach the Node.js API. Verify server/server.js is running and the host forwards requests to its PORT."
                ))
            }
            throw AccountHTTPError(status: http.statusCode, message: payload["error"] as? String ?? "Account server error (\(http.statusCode))")
        }
        return payload
    }
}

struct FirstRunSetupView: View {
    @AppStorage("appLanguage") private var language = "ru"
    @AppStorage("isDarkTheme") private var isDarkTheme = true
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [XiPalette.cyan.opacity(0.16), Color(uiColor: .systemBackground), XiPalette.violet.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                Spacer()
                Label("Xi Lite", systemImage: "sparkles").font(.largeTitle.bold()).foregroundStyle(XiPalette.gradient)
                Text(appText("Добро пожаловать", "Welcome")).font(.title2.weight(.semibold))
                Picker(appText("Язык", "Language"), selection: $language) {
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                }.pickerStyle(.segmented)
                Picker(appText("Оформление", "Appearance"), selection: $isDarkTheme) {
                    Text(appText("Тёмное", "Dark")).tag(true)
                    Text(appText("Светлое", "Light")).tag(false)
                }.pickerStyle(.segmented)
                Button { hasCompletedSetup = true } label: {
                    Text(appText("Продолжить", "Continue"))
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(XiPalette.gradient, in: Capsule()).foregroundStyle(.white)
                }
                Spacer()
            }
            .padding(28)
            .frame(maxWidth: 460)
        }
        .preferredColorScheme(isDarkTheme ? .dark : .light)
    }
}

struct AccountLoginView: View {
    @EnvironmentObject private var account: AccountSessionStore
    @AppStorage("isDarkTheme") private var isDarkTheme = true
    @State private var name = ""
    @State private var pin = ""
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [XiPalette.cyan.opacity(0.16), Color(uiColor: .systemBackground), XiPalette.red.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Label("Xi Lite", systemImage: "sparkles").font(.largeTitle.bold()).foregroundStyle(XiPalette.gradient)
                Text(appText("Аккаунт Xi Lite", "Xi Lite account")).font(.title2.weight(.semibold))
                TextField(appText("Имя аккаунта", "Account name"), text: $name)
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(13).glassSurface(cornerRadius: 16)
                SecureField(appText("PIN-код · 4–12 цифр", "PIN · 4–12 digits"), text: $pin)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .padding(13).glassSurface(cornerRadius: 16)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                Button { authenticate(register: true) } label: {
                    HStack { Spacer(); if isWorking { ProgressView().tint(.white) }; Text(appText("Создать аккаунт", "Create account")).font(.headline); Spacer() }
                        .padding(14).background(XiPalette.gradient, in: Capsule()).foregroundStyle(.white)
                }.disabled(isWorking)
                Button(appText("Уже есть аккаунт? Войти", "Already registered? Sign in")) { authenticate(register: false) }
                    .frame(maxWidth: .infinity).padding(.vertical, 8).disabled(isWorking)
                Text(appText("Аккаунт нужен для статуса Pro; сессия действует неделю.", "An account is used for Pro status; sessions last one week."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(26).frame(maxWidth: 460)
        }
        .preferredColorScheme(isDarkTheme ? .dark : .light)
        .onAppear { if error == nil { error = account.lastError } }
    }

    private func authenticate(register: Bool) {
        guard !isWorking else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                if register { try await account.register(name: name, pin: pin) }
                else { try await account.login(name: name, pin: pin) }
            } catch let authenticationError { error = authenticationError.localizedDescription }
        }
    }
}

let xiLiteProURL = URL(string: "https://i.delta.chat/#E0C5077E3D597BD2CCC271B4A6B3A09BF4B0A68C&v=3&i=1GDEFcoQ5zZih6UxRO25Wioj&s=cKS9dIcvUNh3Yu78MKyede-T&a=euirnwqlh%40nine.testrun.org&n=%D0%A2%D0%B5%D1%85+%D0%9F%D0%BE%D0%B4%D0%B4%D0%B5%D1%80%D0%B6%D0%BA%D0%B0+Xi+Lite")!

struct ProLockedView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var account: AccountSessionStore
    let feature: String
    @State private var showComparison = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36, weight: .semibold)).foregroundStyle(XiPalette.gradient)
                        .frame(maxWidth: .infinity)
                    Text(appText("Xi Lite Pro", "Xi Lite Pro")).font(.largeTitle.bold()).frame(maxWidth: .infinity)
                    Text(appText("\(feature) и расширенные возможности.", "\(feature) and more, unlocked."))
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    ForEach([
                        appText("Pollinations.ai и больше провайдеров", "Pollinations.ai and more providers"),
                        appText("Персональные и собственные градиентные темы", "Preset and custom gradient themes"),
                        appText("Память чата до 50 сообщений", "Conversation context up to 50 messages"),
                        appText("Свои системные инструкции", "Custom system instructions"),
                        appText("Файлы и изображения для vision-моделей", "Files and images for vision models"),
                        appText("Голосовой режим со всеми провайдерами чата", "Voice mode with every chat provider"),
                        appText("Экспорт чатов и виджеты", "Chat export and home widgets"),
                        appText("Закреплённые чаты", "Pinned chats"),
                        appText("Фото-фон интерфейса", "Photo backgrounds"),
                        appText("Инструменты для файлов, папок и ZIP-архивов", "Tools for files, folders, and ZIP archives"),
                        appText("Неограниченные чаты и Pro-браузер", "Unlimited chats and Pro browser")
                    ], id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle.fill").foregroundStyle(.primary)
                    }
                    Text(appText("Также в Xi Lite", "Also included in Xi Lite"))
                        .font(.headline).padding(.top, 6)
                    ForEach([
                        appText("Автоматические названия чатов по первому ответу ИИ", "AI-generated chat titles after the first reply"),
                        appText("Выделение фрагментов, копирование и перегенерация ответов", "Select text fragments, copy, and regenerate replies"),
                        appText("Редактирование отправленных сообщений", "Edit sent messages"),
                        appText("Ссылки на найденные источники во время поиска", "Search source links shown during lookup"),
                        appText("Виброотклик при потоковой генерации", "Haptics during streamed answers")
                    ], id: \.self) { item in
                        Label(item, systemImage: "checkmark")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !account.isPremium {
                        Link(appText("Получить Pro", "Get Pro"), destination: xiLiteProURL)
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(XiPalette.gradient, in: Capsule()).foregroundStyle(.white)
                    }
                    Button(appText("Сравнить бесплатный план и Pro", "Compare Free and Pro")) { showComparison = true }
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                    Button(appText("Закрыть", "Close")) { dismiss() }
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
        }
        .sheet(isPresented: $showComparison) { PlanComparisonView() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct PlanComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var account: AccountSessionStore

    var body: some View {
        NavigationStack {
            List {
                Section(appText("Ограничения бесплатного плана", "Free plan limits")) {
                    comparisonRow(appText("Чаты", "Chats"), appText("До 10 сохранённых чатов", "Up to 10 saved chats"), appText("Без ограничений", "Unlimited"))
                    comparisonRow(appText("Сообщения", "Messages"), appText("100 в день", "100 per day"), appText("Без дневного лимита Xi Lite", "No Xi Lite daily cap"))
                    comparisonRow(appText("Провайдеры", "Providers"), appText("Groq и LLM7.io", "Groq and LLM7.io"), appText("Плюс Pollinations.ai", "Plus Pollinations.ai"))
                    comparisonRow(appText("Контекст чата", "Chat context"), appText("Последние 24 сообщения", "Latest 24 messages"), appText("Последние 50 сообщений", "Latest 50 messages"))
                }
                Section(appText("Возможности", "Features")) {
                    comparisonRow(appText("Темы оформления", "Themes"), appText("Стандартная", "Standard"), appText("Пресеты и собственные градиенты", "Presets and custom gradients"))
                    comparisonRow("System prompt", appText("Недоступен", "Unavailable"), appText("Свои инструкции", "Custom instructions"))
                    comparisonRow(appText("Файлы и изображения", "Files and images"), appText("Недоступны", "Unavailable"), appText("Текст и изображения для поддерживаемых моделей", "Text and images for supported models"))
                    comparisonRow(appText("Голосовой режим", "Voice mode"), appText("Недоступен", "Unavailable"), appText("Все провайдеры: Groq, LLM7.io и Pollinations.ai", "All providers: Groq, LLM7.io, and Pollinations.ai"))
                    comparisonRow(appText("Экспорт чатов", "Chat export"), appText("Нет", "No"), appText("Да", "Yes"))
                    comparisonRow(appText("Браузер и виджеты", "Browser and widgets"), appText("Нет", "No"), appText("Да", "Yes"))
                    comparisonRow(appText("Закрепление чатов", "Pinned chats"), appText("Нет", "No"), appText("Да", "Yes"))
                    comparisonRow(appText("Фото-фон", "Photo background"), appText("Нет", "No"), appText("Своё фото из медиатеки", "Choose a photo from your library"))
                    comparisonRow(appText("Файловые инструменты", "File tools"), appText("Нет", "No"), appText("Создание и редактирование текстовых файлов и папок", "Create/edit text files and folders"))
                    comparisonRow(appText("ZIP-архивы", "ZIP archives"), appText("Нет", "No"), appText("Собрать файлы и папки в скачиваемый ZIP", "Package files and folders into a downloadable ZIP"))
                    comparisonRow(appText("Действия с сообщениями", "Message actions"), appText("Редактирование, выделение, копирование и перегенерация", "Edit, select, copy, and regenerate"), appText("То же", "Same"))
                    comparisonRow(appText("Название чата", "Chat title"), appText("Генерируется ИИ", "Generated by AI"), appText("Генерируется ИИ", "Generated by AI"))
                    comparisonRow(appText("Поиск", "Search"), appText("Показывает найденные ссылки", "Shows returned source links"), appText("Показывает найденные ссылки", "Shows returned source links"))
                    comparisonRow(appText("Виброотклик", "Haptics"), appText("Во время генерации", "During generation"), appText("Во время генерации", "During generation"))
                    comparisonRow(appText("Автосмена провайдера", "Provider fallback"), appText("Нет", "No"), appText("Да", "Yes"))
                }
                if !account.isPremium {
                    Section {
                    Link(appText("Получить Pro", "Get Pro"), destination: xiLiteProURL)
                        .font(.headline).foregroundStyle(XiPalette.cyan)
                    }
                }
            }
            .navigationTitle(appText("Сравнение планов", "Plan comparison"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(appText("Готово", "Done")) { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func comparisonRow(_ feature: String, _ free: String, _ pro: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(feature).font(.subheadline.weight(.semibold))
            HStack(alignment: .top) {
                Label(free, systemImage: "person").frame(maxWidth: .infinity, alignment: .leading)
                Label(pro, systemImage: "sparkles").frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(XiPalette.cyan)
            }
            .font(.caption)
        }
        .padding(.vertical, 3)
    }
}

struct BrowserTab: Identifiable, Codable, Equatable {
    var id = UUID()
    var url = "https://www.google.com"
    var title = "Google"
}

struct BrowserWebView: UIViewRepresentable {
    @Binding var address: String
    @Binding var title: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    var onCreate: (WKWebView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(address: $address, title: $title, canGoBack: $canGoBack, canGoForward: $canGoForward) }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        onCreate(view)
        if let url = URL(string: address) { view.load(URLRequest(url: url)) }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard let url = URL(string: address), view.url?.absoluteString != url.absoluteString else { return }
        view.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var address: Binding<String>
        var title: Binding<String>
        var canGoBack: Binding<Bool>
        var canGoForward: Binding<Bool>
        init(address: Binding<String>, title: Binding<String>, canGoBack: Binding<Bool>, canGoForward: Binding<Bool>) {
            self.address = address
            self.title = title
            self.canGoBack = canGoBack
            self.canGoForward = canGoForward
        }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            canGoBack.wrappedValue = webView.canGoBack
            canGoForward.wrappedValue = webView.canGoForward
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let value = webView.url?.absoluteString { address.wrappedValue = value }
            title.wrappedValue = webView.title ?? webView.url?.host ?? "Google"
            canGoBack.wrappedValue = webView.canGoBack
            canGoForward.wrappedValue = webView.canGoForward
        }
    }
}

struct XiBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("browserTabs") private var savedTabsData = Data()
    @AppStorage("browserSelectedTabID") private var savedSelectedTabID = ""
    @State private var tabs: [BrowserTab] = []
    @State private var selectedTabID: UUID?
    @State private var address = "https://www.google.com"
    @State private var pageTitle = "Google"
    @State private var addressDraft = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var activeWebView: WKWebView?
    @FocusState private var addressFocused: Bool

    private var selectedIndex: Int? { tabs.firstIndex(where: { $0.id == selectedTabID }) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Button { activeWebView?.goBack() } label: { Image(systemName: "chevron.left").frame(width: 34, height: 38) }
                        .disabled(!canGoBack)
                    TextField("Google / URL", text: $addressDraft)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .focused($addressFocused).submitLabel(.go)
                        .onSubmit { navigate(addressDraft) }
                        .padding(.horizontal, 10).padding(.vertical, 7).glassSurface(cornerRadius: 14)
                    Button { navigate(addressDraft) } label: { Image(systemName: "arrow.right").frame(width: 34, height: 38) }
                        .disabled(addressDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button { addTab() } label: { Image(systemName: "plus").frame(width: 34, height: 38) }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)

                if tabs.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(tabs) { tab in
                                HStack(spacing: 7) {
                                    Button { select(tab) } label: { Text(tab.title).lineLimit(1).frame(maxWidth: 140) }
                                    Button { close(tab) } label: { Image(systemName: "xmark").font(.caption2) }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .glassSurface(cornerRadius: 13)
                                .opacity(tab.id == selectedTabID ? 1 : 0.65)
                            }
                        }.padding(.horizontal, 12)
                    }.scrollIndicators(.hidden)
                }

                BrowserWebView(address: $address, title: $pageTitle, canGoBack: $canGoBack, canGoForward: $canGoForward) { activeWebView = $0 }
                    .onChange(of: address) { _, value in addressDraft = value; persistCurrentTab() }
                    .onChange(of: pageTitle) { _, value in persistCurrentTab(title: value) }
            }
            .navigationTitle(pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark") } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { activeWebView?.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!canGoForward)
                    Button { navigate("https://www.google.com") } label: { Image(systemName: "house") }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear(perform: restoreTabs)
    }

    private func navigate(_ input: String) {
        addressFocused = false
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil {
            address = url.absoluteString
        } else if value.contains(".") && !value.contains(" "), let url = URL(string: "https://" + value) {
            address = url.absoluteString
        } else {
            let query = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            address = "https://www.google.com/search?q=\(query)"
        }
        addressDraft = address
        persistCurrentTab()
    }

    private func restoreTabs() {
        if let decoded = try? JSONDecoder().decode([BrowserTab].self, from: savedTabsData), !decoded.isEmpty {
            tabs = decoded
        } else {
            tabs = [BrowserTab()]
        }
        let restoredID = UUID(uuidString: savedSelectedTabID)
        selectedTabID = restoredID.flatMap { id in tabs.contains(where: { $0.id == id }) ? id : nil } ?? tabs.first?.id
        if let selected = tabs.first(where: { $0.id == selectedTabID }) { address = selected.url; addressDraft = selected.url; pageTitle = selected.title }
        persistTabs()
    }

    private func addTab() {
        let tab = BrowserTab()
        tabs.append(tab); selectedTabID = tab.id; address = tab.url; addressDraft = tab.url; pageTitle = tab.title; persistTabs()
    }

    private func select(_ tab: BrowserTab) {
        selectedTabID = tab.id; address = tab.url; addressDraft = tab.url; pageTitle = tab.title; persistTabs()
    }

    private func close(_ tab: BrowserTab) {
        tabs.removeAll { $0.id == tab.id }
        if tabs.isEmpty { addTab() }
        else if selectedTabID == tab.id, let next = tabs.first { select(next) }
        persistTabs()
    }

    private func persistCurrentTab(title: String? = nil) {
        guard let index = selectedIndex else { return }
        tabs[index].url = address
        tabs[index].title = title ?? pageTitle
        persistTabs()
    }

    private func persistTabs() {
        if let data = try? JSONEncoder().encode(tabs) { savedTabsData = data }
        savedSelectedTabID = selectedTabID?.uuidString ?? ""
    }
}

struct ChatHomeView: View {
    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var account: AccountSessionStore
    @EnvironmentObject private var localModels: LocalModelLibrary
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appLanguage") private var appLanguage = "ru"
    @AppStorage("useLocalGGUFModel") private var useLocalGGUFModel = false
    @StateObject private var voiceController = VoiceController()
    @State private var isSidebarPresented = false
    @State private var isSettingsPresented = false
    @State private var isBrowserPresented = false
    @State private var isProGatePresented = false
    @State private var proGateFeature = ""
    @State private var isFileImporterPresented = false
    @State private var isFileExporterPresented = false
    @State private var exportedFileDocument: ChatFileDocument?
    @State private var exportedFilename = "download.txt"
    @State private var attachedImages: [String] = []
    @State private var attachedDocumentText = ""
    @State private var selectedChatPhoto: PhotosPickerItem?
    @AppStorage("gradientPalette") private var activeGradientPalette = "xi"
    @AppStorage("customGradientColor1") private var activeCustomColorOne = "12F4FF"
    @AppStorage("customGradientColor2") private var activeCustomColorTwo = "8C47FF"
    @AppStorage("customGradientColor3") private var activeCustomColorThree = "FF315A"
    @AppStorage("chatBackgroundPhotoBase64") private var chatBackgroundPhotoBase64 = ""
    @State private var draft = ""
    @State private var webSearchEnabled = false
    @State private var clarificationDraft = ""
    @State private var composerBorderRotation = 0.0
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                if let chat = store.currentChat, !chat.messages.isEmpty {
                    conversation(chat)
                } else {
                    welcome
                }
                if let error = store.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 8)
                }
                composer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(surfaceBackground.ignoresSafeArea())
        .sheet(isPresented: $isSidebarPresented) { ChatSidebarView() }
        .sheet(isPresented: $isSettingsPresented) { SettingsView() }
        .sheet(isPresented: $isBrowserPresented) {
            if account.isPremium { XiBrowserView() } else { ProLockedView(feature: appText("Браузер", "Browser")) }
        }
        .sheet(isPresented: $isProGatePresented) { ProLockedView(feature: proGateFeature.isEmpty ? appText("Возможности Pro", "Pro features") : proGateFeature) }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.text, .plainText], allowsMultipleSelection: true, onCompletion: importFiles)
        .fileExporter(isPresented: $isFileExporterPresented, document: exportedFileDocument, contentType: exportedFileContentType, defaultFilename: exportedFilename) { result in
            if case .failure(let error) = result { store.errorMessage = error.localizedDescription }
        }
        .onChange(of: selectedChatPhoto) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpeg = resizedJPEG(image), jpeg.count <= 4_000_000 else {
                    store.errorMessage = appText("Не удалось загрузить это изображение.", "Could not load this image.")
                    return
                }
                attachedImages.append(jpeg.base64EncodedString())
                store.errorMessage = nil
            }
        }
    }

    private var surfaceBackground: Color {
        colorScheme == .dark ? Color(red: 0.025, green: 0.025, blue: 0.04) : Color(red: 0.97, green: 0.975, blue: 1.0)
    }

    private var background: some View {
        let _ = (activeGradientPalette, activeCustomColorOne, activeCustomColorTwo, activeCustomColorThree, chatBackgroundPhotoBase64)
        return ZStack {
            if account.isPremium, let data = Data(base64Encoded: chatBackgroundPhotoBase64), let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay(surfaceBackground.opacity(colorScheme == .dark ? 0.56 : 0.34))
                    .overlay(XiPalette.gradient.opacity(0.12))
                    .clipped()
            } else {
                surfaceBackground
                RadialGradient(colors: [XiPalette.red.opacity(colorScheme == .dark ? 0.42 : 0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 560)
                RadialGradient(colors: [XiPalette.cyan.opacity(colorScheme == .dark ? 0.34 : 0.24), .clear], center: .bottomLeading, startRadius: 0, endRadius: 500)
                RadialGradient(colors: [XiPalette.violet.opacity(colorScheme == .dark ? 0.22 : 0.14), .clear], center: .center, startRadius: 10, endRadius: 380)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            Button { isSidebarPresented = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 46)
                    .glassSurface(cornerRadius: 23)
            }
            .accessibilityLabel(appText("История чатов", "Chat history"))

            Button { isBrowserPresented = true } label: {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 42, height: 46)
                    .glassSurface(cornerRadius: 23)
            }
            .accessibilityLabel(appText("Браузер", "Browser"))

            Spacer()
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .foregroundStyle(XiPalette.gradient)
                Text("Xi Lite")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.primary)
            Spacer()

            if account.isPremium, let chat = store.currentChat, !chat.messages.isEmpty {
                ShareLink(item: chat.exportText, subject: Text(chat.title)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 38, height: 46)
                }
                .accessibilityLabel(appText("Экспортировать чат", "Export chat"))
            }

            Button {
                if store.createChat() == nil { isProGatePresented = true }
            } label: {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 46)
                    .glassSurface(cornerRadius: 23)
            }
            .accessibilityLabel(appText("Новый чат", "New chat"))
        }
        .foregroundStyle(.primary)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 36)
            VStack(alignment: .leading, spacing: 9) {
                Text(appText("ТВОЙ ИИ-ПОМОЩНИК", "YOUR AI ASSISTANT"))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(XiPalette.gradient)
                Text(appText("Как я могу помочь?", "How can I help?"))
                    .font(.system(size: 29, weight: .medium, design: .rounded))
                    .tracking(-1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.primary)
            }
            .padding(.bottom, 4)

            suggestion(icon: "sparkles", title: appText("Объясни простыми словами, как работает ИИ", "Explain how AI works in simple terms")) {
                submit(appText("Объясни простыми словами, как работает ИИ", "Explain how AI works in simple terms"), webSearch: false)
            }
            suggestion(icon: "leaf", title: appText("Составь план питания на неделю", "Create a weekly meal plan")) {
                submit(appText("Составь простой план питания на неделю", "Create a simple weekly meal plan"), webSearch: false)
            }
            suggestion(icon: "globe.americas", title: appText("Найди последние новости о технологиях", "Find the latest technology news")) {
                submit(appText("Найди последние новости о технологиях и кратко перескажи", "Find the latest technology news and summarize it"), webSearch: true)
            }

            Spacer(minLength: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func suggestion(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.78))
                    .frame(width: 26)
                Text(title).font(.system(size: 15, weight: .medium))
                Spacer()
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.65))
            }
                    .foregroundStyle(.primary.opacity(0.88))
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .glassSurface(cornerRadius: 19)
        }
        .buttonStyle(.plain)
    }

    private func conversation(_ chat: ChatThread) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(chat.messages) { message in
                        MessageBubble(
                            message: message,
                            onEdit: { updatedText in
                                Task { await store.editUserMessage(message.id, in: chat.id, text: updatedText) }
                            },
                            onRegenerate: {
                                Task { await store.regenerateAssistant(message.id, in: chat.id) }
                            },
                            onExportFile: exportGeneratedFile
                        )
                            .id(message.id)
                    }
                    if store.isSending && !store.activityItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                ProgressView().tint(.cyan)
                                Text(store.statusMessage ?? appText("Выполняю поиск или инструмент…", "Searching or running a tool…"))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                            }
                            ForEach(store.activityItems.suffix(6)) { activity in
                                if let address = activity.url, let url = URL(string: address) {
                                    Link(destination: url) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Label(activity.title, systemImage: activity.title.localizedCaseInsensitiveContains("Tavily") || activity.title.localizedCaseInsensitiveContains("поиск") ? "magnifyingglass" : "safari")
                                                .font(.caption.weight(.medium)).lineLimit(2)
                                            Text(url.host ?? address).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .tint(XiPalette.cyan)
                                } else {
                                    Label(activity.title, systemImage: "wrench.and.screwdriver")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            if let question = store.clarificationQuestion {
                                Text(question)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 8) {
                                    TextField(appText("Ответь, чтобы продолжить…", "Reply to continue…"), text: $clarificationDraft, axis: .vertical)
                                        .lineLimit(1...3)
                                        .textFieldStyle(.roundedBorder)
                                    Button {
                                        store.submitClarification(clarificationDraft)
                                        clarificationDraft = ""
                                    } label: {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .font(.title2).foregroundStyle(XiPalette.cyan)
                                    }
                                    .disabled(clarificationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    .accessibilityLabel(appText("Отправить уточнение", "Send clarification"))
                                }
                            }
                        }
                        .padding(11)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 5)
                    }
                }
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
            .onChange(of: chat.messages.count) { _, _ in
                if let last = chat.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                Button { isSettingsPresented = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.8))
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel(appText("Настройки и память", "Settings and memory"))

                Button {
                    if account.isPremium { isFileImporterPresented = true }
                    else { presentProGate(appText("Загрузка текстовых файлов и изображений", "Text and image uploads")) }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.8))
                        .frame(width: 30, height: 34)
                }
                .accessibilityLabel(appText("Добавить файл или изображение", "Attach a text file or image"))

                if account.isPremium {
                    PhotosPicker(selection: $selectedChatPhoto, matching: .images) {
                        Image(systemName: "photo")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.8))
                            .frame(width: 28, height: 34)
                    }
                    .accessibilityLabel(appText("Выбрать фото", "Choose a photo"))
                }

                TextField(appText("Спроси Xi Lite…", "Ask Xi Lite…"), text: $draft, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.done)
                    .onSubmit { inputFocused = false }
                    .tint(.cyan)
                    .padding(.vertical, 5)

                Button { webSearchEnabled.toggle() } label: {
                    Image(systemName: webSearchEnabled ? "globe.americas.fill" : "globe.americas")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(webSearchEnabled ? XiPalette.cyan : Color.secondary)
                        .frame(width: 32, height: 34)
                }
                .accessibilityLabel(webSearchEnabled ? appText("Выключить поиск в сети", "Turn off web search") : appText("Включить поиск в сети", "Turn on web search"))
                .disabled(useLocalGGUFModel)

                Button(action: toggleVoiceRecording) {
                    if voiceController.isTranscribing {
                        ProgressView().tint(XiPalette.cyan)
                            .frame(width: 32, height: 34)
                    } else {
                        Image(systemName: voiceController.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(voiceController.isRecording ? .red : Color.secondary)
                            .frame(width: 32, height: 34)
                    }
                }
                .disabled(voiceController.isTranscribing || store.isSending)
                .accessibilityLabel(voiceController.isRecording ? appText("Остановить запись и отправить", "Stop and send recording") : appText("Голосовой ввод · Бета", "Voice input · Beta"))
                .overlay(alignment: .topTrailing) {
                    if !account.isPremium {
                        Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold))
                            .padding(3).background(.ultraThinMaterial, in: Circle()).offset(x: 2, y: -2)
                    }
                }

                let canStop = store.isSending || voiceController.isSpeaking
                Button(action: canStop ? stopResponse : send) {
                    Image(systemName: canStop ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(canStop ? AnyShapeStyle(Color.red) : AnyShapeStyle(XiPalette.gradient), in: Circle())
                        .glassEffect(.regular, in: .circle)
                }
                .disabled(!canStop && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedImages.isEmpty && attachedDocumentText.isEmpty)
                .opacity(!canStop && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedImages.isEmpty && attachedDocumentText.isEmpty ? 0.55 : 1)
                .accessibilityLabel(canStop ? appText("Остановить ответ", "Stop response") : appText("Отправить сообщение", "Send message"))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                XiPalette.gradient.opacity(inputFocused ? 0.15 : 0.10),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.42), XiPalette.cyan.opacity(0.38), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .overlay {
                let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
                let border = AngularGradient(
                    colors: [XiPalette.cyan, .blue, XiPalette.red, .pink, XiPalette.cyan],
                    center: .center,
                    angle: .degrees(composerBorderRotation)
                )
                ZStack {
                    shape.stroke(border, lineWidth: 4)
                        .blur(radius: 7)
                        .opacity(inputFocused ? 0.72 : 0.42)
                    shape.stroke(border, lineWidth: inputFocused ? 1.8 : 1.2)
                        .opacity(inputFocused ? 1 : 0.78)
                }
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                    composerBorderRotation = 360
                }
            }

            HStack {
                Label(
                    useLocalGGUFModel
                        ? appText("Локально · \(localModels.selectedModel?.name ?? "GGUF не выбрана")", "Local · \(localModels.selectedModel?.name ?? "No GGUF selected")")
                        : "\(store.selectedProvider.title) · \(GroqModel.available.first(where: { $0.id == store.selectedModelID })?.title ?? store.selectedModelID)",
                    systemImage: useLocalGGUFModel ? "iphone" : "sparkles"
                )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if webSearchEnabled {
                    Label(appText("Поиск в сети", "Web search"), systemImage: "globe")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.cyan.opacity(0.85))
                }
                if voiceController.isRecording {
                    Spacer()
                    Label(appText("Запись · нажми, чтобы отправить", "Recording · tap to send"), systemImage: "waveform")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red)
                } else if voiceController.isTranscribing {
                    Spacer()
                    Label(appText("Распознавание речи…", "Transcribing…"), systemImage: "waveform")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if !attachedImages.isEmpty || !attachedDocumentText.isEmpty {
                    Spacer()
                    Label(appText("Вложения готовы", "Attachments ready"), systemImage: "paperclip")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(XiPalette.cyan)
                }
            }
            .padding(.horizontal, 5)
            if let error = voiceController.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 5)
            }
        }
    }

    private func send() {
        submit(draft)
    }

    private func stopResponse() {
        if store.isSending { store.stopGenerating() }
        voiceController.stopSpeaking()
        voiceController.cancelRecording()
    }

    private func toggleVoiceRecording() {
        guard account.isPremium else {
            presentProGate(appText("Голосовой режим со всеми провайдерами", "Voice mode with all providers"))
            return
        }
        if voiceController.isRecording {
            Task {
                guard let transcript = await voiceController.stopAndTranscribe() else { return }
                submit(transcript, webSearch: webSearchEnabled, speakResponse: true)
            }
        } else {
            Task { await voiceController.startRecording() }
        }
    }

    private func presentProGate(_ feature: String) {
        proGateFeature = feature
        isProGatePresented = true
    }

    private func submit(_ message: String, webSearch: Bool? = nil, speakResponse: Bool = false) {
        guard (!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedImages.isEmpty || !attachedDocumentText.isEmpty), !store.isSending else { return }
        if speakResponse && !account.isPremium {
            presentProGate(appText("Голосовой режим доступен в Pro", "Voice mode is available with Pro"))
            return
        }
        if (!attachedImages.isEmpty || !attachedDocumentText.isEmpty) && !account.isPremium {
            presentProGate(appText("Загрузка файлов доступна в Pro", "File uploads are available with Pro"))
            return
        }
        let shouldSearch = webSearch ?? webSearchEnabled
        if let webSearch { webSearchEnabled = webSearch }
        let prompt = [message, attachedDocumentText].filter { !$0.isEmpty }.joined(separator: "\n\n")
        let finalPrompt = prompt.isEmpty && !attachedImages.isEmpty ? appText("Опиши это изображение.", "Describe this image.") : prompt
        let images = attachedImages
        attachedImages.removeAll()
        attachedDocumentText = ""
        draft = ""
        inputFocused = false
        Task {
            await store.send(finalPrompt, imageData: images, webSearch: shouldSearch) { answer in
                guard speakResponse else { return }
                voiceController.speak(answer)
            }
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard account.isPremium else {
            presentProGate(appText("Загрузка текстовых файлов доступна в Pro", "Text-file uploads are available with Pro"))
            return
        }
        do {
            for url in try result.get() {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                let type = UTType(filenameExtension: url.pathExtension) ?? .data
                guard type.conforms(to: .text) else {
                    throw ChatError.server(appText("Здесь можно выбрать только текстовые файлы. Для фото используй кнопку изображения.", "Only text files can be selected here. Use the photo button for images."))
                }
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw ChatError.server(appText("Поддерживаются только текстовые файлы UTF-8.", "Only UTF-8 text files are supported."))
                }
                attachedDocumentText += "\n\n[\(url.lastPathComponent)]\n\(String(text.prefix(100_000)))"
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func exportGeneratedFile(_ file: ChatFileAttachment) {
        guard let data = Data(base64Encoded: file.contentsBase64) else {
            store.errorMessage = appText("Не удалось прочитать созданный файл.", "Could not read the generated file.")
            return
        }
        exportedFileDocument = ChatFileDocument(contents: data)
        exportedFilename = URL(fileURLWithPath: file.filename).lastPathComponent
        isFileExporterPresented = true
    }

    private var exportedFileContentType: UTType {
        UTType(filenameExtension: URL(fileURLWithPath: exportedFilename).pathExtension) ?? .plainText
    }
}

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(number: String, text: String)
    case code(String)
    case spacer

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var insideCode = false

        func flushParagraph() {
            let value = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { blocks.append(.paragraph(value)) }
            paragraph.removeAll(keepingCapacity: true)
        }

        for sourceLine in markdown.components(separatedBy: .newlines) {
            let line = sourceLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if insideCode {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll(keepingCapacity: true)
                } else {
                    flushParagraph()
                }
                insideCode.toggle()
                continue
            }
            if insideCode {
                codeLines.append(sourceLine)
                continue
            }
            if line.isEmpty {
                flushParagraph()
                if blocks.last.map({ if case .spacer = $0 { return true }; return false }) != true {
                    blocks.append(.spacer)
                }
                continue
            }

            let headingLevel = line.prefix(while: { $0 == "#" }).count
            if (1...3).contains(headingLevel), line.dropFirst(headingLevel).first == " " {
                flushParagraph()
                let title = String(line.dropFirst(headingLevel)).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: headingLevel, text: title))
                continue
            }
            if let bullet = ["- ", "* ", "• "].first(where: { line.hasPrefix($0) }) {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(bullet.count))))
                continue
            }

            let numberPattern = #"^(\d{1,2})[.)]\s+(.+)$"#
            if let match = line.range(of: numberPattern, options: .regularExpression),
               let numberRange = line.range(of: #"^\d{1,2}"#, options: .regularExpression) {
                flushParagraph()
                let number = String(line[numberRange])
                let remainder = String(line[match]).dropFirst(number.count + 2)
                blocks.append(.numbered(number: number, text: String(remainder)))
                continue
            }
            paragraph.append(line)
        }

        flushParagraph()
        if !codeLines.isEmpty { blocks.append(.code(codeLines.joined(separator: "\n"))) }
        while let last = blocks.last, case .spacer = last { blocks.removeLast() }
        return blocks
    }
}

struct MarkdownResponseView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlock.parse(markdown).enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(markdownText(text))
                .font(.system(size: level == 1 ? 24 : level == 2 ? 21 : 18, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, level == 1 ? 10 : 5)
                .padding(.bottom, 1)
                .textSelection(.enabled)
        case .paragraph(let text):
            Text(markdownText(text))
                .font(.system(size: 17))
                .lineSpacing(5)
                .foregroundStyle(.primary.opacity(0.94))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Circle().fill(XiPalette.cyan).frame(width: 7, height: 7)
                Text(markdownText(text))
                    .font(.system(size: 17))
                    .lineSpacing(4)
                    .foregroundStyle(.primary.opacity(0.94))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.leading, 3)
        case .numbered(let number, let text):
            HStack(alignment: .top, spacing: 12) {
                Text(number)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(XiPalette.cyan)
                    .frame(width: 28, height: 28)
                    .background(XiPalette.cyan.opacity(0.12), in: Circle())
                    .textSelection(.enabled)
                Text(markdownText(text))
                    .font(.system(size: 17))
                    .lineSpacing(4)
                    .foregroundStyle(.primary.opacity(0.94))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 3)
        case .code(let code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(XiPalette.cyan)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
            }
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        case .spacer:
            Color.clear.frame(height: 4)
        }
    }

    private func markdownText(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source)) ?? AttributedString(source)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let onEdit: (String) -> Void
    let onRegenerate: () -> Void
    let onExportFile: (ChatFileAttachment) -> Void
    @State private var isEditing = false
    @State private var editedText = ""
    @State private var isSelectionPresented = false

    var body: some View {
        Group {
            if message.role == "assistant" {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(XiPalette.gradient)
                        .frame(width: 27, height: 27)
                        .background(Color.primary.opacity(0.08), in: Circle())
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Xi Lite")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(XiPalette.gradient)
                        if !message.content.isEmpty {
                            MarkdownResponseView(markdown: message.content)
                        }
                        if let files = message.files, !files.isEmpty {
                            ForEach(files) { file in
                                Button { onExportFile(file) } label: {
                                    Label(appText("Скачать \(file.filename)", "Download \(file.filename)"), systemImage: "arrow.down.doc.fill")
                                        .font(.subheadline.weight(.medium))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .background(XiPalette.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if !message.content.isEmpty {
                            HStack(spacing: 16) {
                                Button {
                                    UIPasteboard.general.string = message.content
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Label(appText("Копировать", "Copy"), systemImage: "doc.on.doc")
                                }
                                Button {
                                    isSelectionPresented = true
                                } label: {
                                    Label(appText("Выделить фрагмент", "Select a fragment"), systemImage: "text.cursor")
                                }
                                Button(action: onRegenerate) {
                                    Label(appText("Ещё раз", "Regenerate"), systemImage: "arrow.clockwise")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .glassSurface(cornerRadius: 22)
            } else {
                HStack {
                    Spacer(minLength: 38)
                    VStack(alignment: .trailing, spacing: 8) {
                        if let images = message.imageData {
                            ForEach(Array(images.enumerated()), id: \.offset) { _, encoded in
                                if let data = Data(base64Encoded: encoded), let image = UIImage(data: data) {
                                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 220, maxHeight: 180).clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                            }
                        }
                        if !message.content.isEmpty {
                            if isEditing {
                                VStack(alignment: .trailing, spacing: 8) {
                                    TextEditor(text: $editedText).frame(minHeight: 70).scrollContentBackground(.hidden)
                                    HStack {
                                        Button(appText("Отмена", "Cancel")) { isEditing = false }
                                        Button(appText("Сохранить и ответить", "Save and reply")) {
                                            let value = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !value.isEmpty else { return }
                                            onEdit(value)
                                            isEditing = false
                                        }
                                        .fontWeight(.semibold)
                                    }
                                }
                                .padding(12)
                                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                            } else {
                                Text(message.content)
                                .font(.system(size: 15)).lineSpacing(4).foregroundStyle(.white).textSelection(.enabled)
                                .padding(.horizontal, 15).padding(.vertical, 12)
                                .background(XiPalette.gradient.opacity(0.76), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                                .glassEffect(.regular, in: .rect(cornerRadius: 21))
                                .overlay { RoundedRectangle(cornerRadius: 21, style: .continuous).strokeBorder(XiPalette.gradient.opacity(0.9), lineWidth: 1) }
                            }
                            if message.role == "user" && !isEditing {
                                Button {
                                    editedText = message.content
                                    isEditing = true
                                } label: {
                                    Label(appText("Изменить", "Edit"), systemImage: "pencil")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isSelectionPresented) {
            SelectableAnswerSheet(text: message.content)
        }
    }
}

struct SelectableAnswerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: String

    var body: some View {
        NavigationStack {
            ScrollView {
                SelectableAnswerText(text: text)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(appText("Выдели и скопируй", "Select and copy"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appText("Готово", "Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct SelectableAnswerText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.text = text
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

struct ChatSidebarView: View {
    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var account: AccountSessionStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "ru"
    @State private var query = ""
    @State private var isProGatePresented = false
    @State private var proGateFeature = ""

    private var filteredChats: [ChatThread] {
        let sorted = store.chats.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                VStack(spacing: 15) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(appText("Поиск по чатам", "Search chats"), text: $query).tint(.cyan)
                    }
                    .padding(13)
                    .glassSurface(cornerRadius: 17)
                    .padding(.horizontal)

                    HStack {
                        Text(appText("Недавнее", "Recent")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text(account.isPremium ? "\(store.chats.count)" : "\(store.chats.count)/10")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 20)

                    if filteredChats.isEmpty {
                        ContentUnavailableView(
                            query.isEmpty ? appText("Нет недавних чатов", "No recent chats") : appText("Ничего не найдено", "No results found"),
                            systemImage: query.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass",
                            description: Text(query.isEmpty ? appText("Начни новый разговор с Xi Lite.", "Start a new conversation with Xi Lite.") : appText("Попробуй изменить запрос.", "Try changing your search."))
                        )
                            .foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        List {
                            ForEach(filteredChats) { chat in
                                Button {
                                    store.select(chat)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "bubble.left")
                                            .foregroundStyle(store.selectedChatID == chat.id ? XiPalette.cyan : Color.secondary)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(chat.title).lineLimit(1).foregroundStyle(.primary)
                                            Text(chat.updatedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if chat.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(XiPalette.cyan) }
                                        if store.selectedChatID == chat.id { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.cyan) }
                                    }
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                }
                                .listRowBackground(Color.clear)
                                .swipeActions {
                                    Button(role: .destructive) { store.delete(chat) } label: { Label(appText("Удалить", "Delete"), systemImage: "trash") }
                                }
                                .contextMenu {
                                    Button {
                                        if account.isPremium { store.togglePin(chat.id) }
                                        else {
                                            proGateFeature = appText("Закрепление чатов доступно в Pro", "Pinning chats is available with Pro")
                                            isProGatePresented = true
                                        }
                                    } label: {
                                        Label(chat.isPinned ? appText("Открепить чат", "Unpin chat") : appText("Закрепить чат · Pro", "Pin chat · Pro"), systemImage: chat.isPinned ? "pin.slash" : "pin")
                                    }
                                    Button(role: .destructive) { store.delete(chat) } label: { Label(appText("Удалить чат", "Delete chat"), systemImage: "trash") }
                                }
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .listStyle(.plain)
                    }
                }
                .padding(.top, 12)
            }
            .navigationTitle(appText("Чаты", "Chats"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.primary.opacity(0.8)) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if store.createChat() != nil { dismiss() }
                        else { isProGatePresented = true }
                    } label: { Image(systemName: "square.and.pencil").foregroundStyle(.cyan) }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(Color(uiColor: .systemBackground))
        .sheet(isPresented: $isProGatePresented) { ProLockedView(feature: proGateFeature.isEmpty ? appText("Неограниченное число чатов", "Unlimited chats") : proGateFeature) }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var account: AccountSessionStore
    @EnvironmentObject private var localModels: LocalModelLibrary
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isDarkTheme") private var isDarkTheme = true
    @AppStorage("appLanguage") private var appLanguage = "ru"
    @AppStorage("customGroqModelID") private var customModelID = ""
    @AppStorage("customLLM7ModelID") private var customLLM7ModelID = ""
    @AppStorage("customPollinationsModelID") private var customPollinationsModelID = ""
    @AppStorage("gradientPalette") private var gradientPalette = "xi"
    @AppStorage("chatBackgroundPhotoBase64") private var chatBackgroundPhotoBase64 = ""
    @AppStorage("autoSwitchProvider") private var autoSwitchProvider = false
    @AppStorage("localToolsEnabled") private var localToolsEnabled = false
    @AppStorage("useLocalGGUFModel") private var useLocalGGUFModel = false
    @AppStorage("profileImageBase64") private var profileImageBase64 = ""
    @State private var apiKey = Keychain.read("groq_api_key") ?? ""
    @State private var llm7APIKey = Keychain.read("llm7_api_key") ?? ""
    @State private var pollinationsAPIKey = Keychain.read("pollinations_api_key") ?? ""
    @State private var searchAPIKey = Keychain.read("tavily_api_key") ?? ""
    @State private var groqModels = GroqModel.available
    @State private var isLoadingGroqModels = false
    @State private var groqModelLoadError: String?
    @State private var llm7Models: [LLM7Model] = []
    @State private var isLoadingLLM7Models = false
    @State private var llm7ModelLoadError: String?
    @State private var pollinationsModels: [PollinationsModel] = [.defaultModel]
    @State private var isLoadingPollinationsModels = false
    @State private var pollinationsModelLoadError: String?
    @State private var newMemory = ""
    @State private var didSave = false
    @State private var saveError: String?
    @State private var didSaveLLM7Key = false
    @State private var llm7KeySaveError: String?
    @State private var didSavePollinationsKey = false
    @State private var pollinationsKeySaveError: String?
    @State private var didSaveSearchKey = false
    @State private var searchKeySaveError: String?
    @State private var customModelError: String?
    @State private var didApplyCustomModel = false
    @State private var editedAccountName = ""
    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var accountActionMessage: String?
    @State private var selectedProfilePhoto: PhotosPickerItem?
    @State private var selectedBackgroundPhoto: PhotosPickerItem?
    @State private var isProOfferPresented = false
    @State private var isPlanComparisonPresented = false
    @State private var isLocalModelLibraryPresented = false
    @State private var themeColorOne = Color(hex: "12F4FF")
    @State private var themeColorTwo = Color(hex: "8C47FF")
    @State private var themeColorThree = Color(hex: "FF315A")

    private func refreshGroqModels() async {
        guard let key = Keychain.read("groq_api_key"), !key.isEmpty else { return }
        isLoadingGroqModels = true
        defer { isLoadingGroqModels = false }
        do {
            groqModels = try await GroqModel.loadCatalog(apiKey: key)
            groqModelLoadError = nil
        } catch {
            groqModelLoadError = error.localizedDescription
        }
    }

    private func refreshLLM7Models() async {
        isLoadingLLM7Models = true
        defer { isLoadingLLM7Models = false }
        do {
            llm7Models = try await LLM7Model.loadCatalog()
            llm7ModelLoadError = nil
        } catch {
            llm7ModelLoadError = error.localizedDescription
        }
    }

    private func refreshPollinationsModels() async {
        guard let key = Keychain.read("pollinations_api_key"), !key.isEmpty else { return }
        isLoadingPollinationsModels = true
        defer { isLoadingPollinationsModels = false }
        do {
            pollinationsModels = try await PollinationsModel.loadCatalog(apiKey: key)
            pollinationsModelLoadError = nil
        } catch {
            pollinationsModelLoadError = error.localizedDescription
        }
    }

    private func freeModelRow(_ modelID: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(modelID)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                Form {
                    Section {
                        SecureField("gsk_…", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !key.isEmpty else {
                                didSave = false
                                saveError = appText("Сначала вставь Groq API-ключ.", "Enter a Groq API key first.")
                                return
                            }
                            do {
                                try Keychain.save(key, account: "groq_api_key")
                                guard Keychain.read("groq_api_key") == key else {
                                    throw ChatError.server(appText("Ключ не найден после сохранения. Попробуй ещё раз.", "The key could not be read after saving. Please try again."))
                                }
                                didSave = true
                                saveError = nil
                                Task { await refreshGroqModels() }
                            } catch {
                                didSave = false
                                saveError = error.localizedDescription
                            }
                        } label: {
                            Label(didSave ? appText("Ключ сохранён", "Key saved") : appText("Сохранить ключ", "Save key"), systemImage: didSave ? "checkmark.circle.fill" : "lock.fill")
                                .foregroundStyle(didSave ? .green : .cyan)
                        }
                        if let saveError {
                            Text(saveError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("Groq API")
                    } footer: {
                        Text(appText("Ключ хранится в Keychain на устройстве. Список моделей загружается из Groq после сохранения ключа.", "The key is stored in the device Keychain. The Groq model list loads after saving the key."))
                    }

                    Section {
                        SecureField("LLM7.io API key", text: $llm7APIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            let key = llm7APIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !key.isEmpty else {
                                didSaveLLM7Key = false
                                llm7KeySaveError = appText("Сначала вставь API-ключ LLM7.io.", "Enter an LLM7.io API key first.")
                                return
                            }
                            do {
                                try Keychain.save(key, account: "llm7_api_key")
                                guard Keychain.read("llm7_api_key") == key else {
                                    throw ChatError.server(appText("Ключ LLM7.io не найден после сохранения.", "The LLM7.io key could not be read after saving."))
                                }
                                didSaveLLM7Key = true
                                llm7KeySaveError = nil
                            } catch {
                                didSaveLLM7Key = false
                                llm7KeySaveError = error.localizedDescription
                            }
                        } label: {
                            Label(didSaveLLM7Key ? appText("Ключ LLM7.io сохранён", "LLM7.io key saved") : appText("Сохранить ключ LLM7.io", "Save LLM7.io key"), systemImage: didSaveLLM7Key ? "checkmark.circle.fill" : "lock.fill")
                                .foregroundStyle(didSaveLLM7Key ? .green : .cyan)
                        }
                        if let llm7KeySaveError { Text(llm7KeySaveError).font(.footnote).foregroundStyle(.red) }
                        Link(appText("Получить ключ LLM7.io", "Get an LLM7.io key"), destination: URL(string: "https://dash.llm7.io/")!)
                    } header: {
                        Text("LLM7.io API")
                    } footer: {
                        Text(appText("Ключ хранится отдельно в Keychain. Используется OpenAI-совместимый API LLM7.io.", "The key is stored separately in Keychain. Uses the OpenAI-compatible LLM7.io API."))
                    }

                    Section {
                        SecureField("Pollinations API key · pk_… / sk_…", text: $pollinationsAPIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            let key = pollinationsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !key.isEmpty else {
                                didSavePollinationsKey = false
                                pollinationsKeySaveError = appText("Вставь API-ключ Pollinations.ai.", "Enter a Pollinations.ai API key.")
                                return
                            }
                            do {
                                try Keychain.save(key, account: "pollinations_api_key")
                                guard Keychain.read("pollinations_api_key") == key else {
                                    throw ChatError.server(appText("Ключ Pollinations.ai не найден после сохранения.", "The Pollinations.ai key could not be read after saving."))
                                }
                                didSavePollinationsKey = true
                                pollinationsKeySaveError = nil
                                Task { await refreshPollinationsModels() }
                            } catch {
                                didSavePollinationsKey = false
                                pollinationsKeySaveError = error.localizedDescription
                            }
                        } label: {
                            Label(didSavePollinationsKey ? appText("Ключ Pollinations.ai сохранён", "Pollinations.ai key saved") : appText("Сохранить ключ Pollinations.ai", "Save Pollinations.ai key"), systemImage: didSavePollinationsKey ? "checkmark.circle.fill" : "lock.fill")
                                .foregroundStyle(didSavePollinationsKey ? .green : .cyan)
                        }
                        if let pollinationsKeySaveError { Text(pollinationsKeySaveError).font(.footnote).foregroundStyle(.red) }
                        Link(appText("Получить API-ключ", "Get an API key"), destination: URL(string: "https://enter.pollinations.ai/keys")!)
                    } header: {
                        Text("Pollinations.ai API")
                    } footer: {
                        Text(appText("Ключ хранится в Keychain и используется для запросов к Pollinations.ai.", "The key is stored in Keychain and used for Pollinations.ai requests."))
                    }

                    Section(appText("Локальные модели · GGUF", "Local models · GGUF")) {
                        if account.isPremium {
                            Label(appText("Бета-функция", "Beta feature"), systemImage: "flask")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(XiPalette.cyan)

                            Toggle(isOn: $useLocalGGUFModel) {
                                Label(appText("Отвечать локальной моделью", "Use on-device model"), systemImage: "iphone")
                            }
                            .tint(XiPalette.cyan)
                            .onChange(of: useLocalGGUFModel) { _, isEnabled in
                                if isEnabled && localModels.selectedModel == nil {
                                    useLocalGGUFModel = false
                                    isLocalModelLibraryPresented = true
                                }
                            }

                            if !localModels.models.isEmpty {
                                Picker(appText("Модель", "Model"), selection: $localModels.selectedModelID) {
                                    ForEach(localModels.models) { model in
                                        Text(model.name).tag(model.id)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            Button {
                                isLocalModelLibraryPresented = true
                            } label: {
                                Label(appText("Импортировать или скачать GGUF…", "Import or download GGUF…"), systemImage: "arrow.down.doc")
                            }

                            Text(appText(
                                "Бета-функция. Импортируй GGUF из Файлов или скачай из Hugging Face. Модель обрабатывает запросы на устройстве; они не отправляются облачному провайдеру. Размер модели ограничен памятью iPhone. Локальный режим принимает только текст.",
                                "Beta feature. Import GGUF files or download from Hugging Face. Prompts are processed on-device and are not sent to a cloud provider. Model size is limited by iPhone memory. Local mode accepts text only."
                            ))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        } else {
                            Label(appText("Бета-функция · только Pro", "Beta feature · Pro only"), systemImage: "flask")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(XiPalette.cyan)
                            Button(appText("Разблокировать локальные модели в Pro", "Unlock local models with Pro")) {
                                isProOfferPresented = true
                            }
                            .foregroundStyle(XiPalette.cyan)
                        }
                    }

                    Section(appText("Провайдер модели", "Model provider")) {
                        Picker(appText("Провайдер", "Provider"), selection: $store.selectedProvider) {
                            ForEach(AIProvider.allCases) { provider in
                                Text(provider == .pollinations && !account.isPremium ? "Pollinations.ai · Pro 🔒" : provider.title).tag(provider)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: store.selectedProvider) { _, provider in
                            guard provider == .pollinations && !account.isPremium else { return }
                            store.selectedProvider = .groq
                            isProOfferPresented = true
                        }
                        if !account.isPremium {
                            Button(appText("Pollinations.ai доступен в Pro", "Pollinations.ai is a Pro feature")) { isProOfferPresented = true }
                                .font(.footnote.weight(.semibold)).foregroundStyle(XiPalette.cyan)
                        }
                    }

                        Section(appText("Модели · \(store.selectedProvider.title)", "Models · \(store.selectedProvider.title)")) {
                            if store.selectedProvider == .groq {
                                Picker(appText("Модель · Groq", "Model · Groq"), selection: $store.selectedModelID) {
                                    ForEach(groqModels) { model in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(model.title)
                                            Text(model.detail).font(.caption).foregroundStyle(.secondary)
                                        }
                                        .tag(model.id)
                                    }
                                    if !groqModels.contains(where: { $0.id == store.selectedModelID }) {
                                        Text("Custom · \(store.selectedModelID)").tag(store.selectedModelID)
                                    }
                                }
                                .pickerStyle(.menu)
                                Button {
                                    guard Keychain.read("groq_api_key")?.isEmpty == false else {
                                        groqModelLoadError = appText("Сначала сохрани Groq API-ключ.", "Save a Groq API key first.")
                                        return
                                    }
                                    Task { await refreshGroqModels() }
                                } label: {
                                    Label(isLoadingGroqModels ? appText("Загружаю модели…", "Loading models…") : appText("Обновить список моделей", "Refresh model list"), systemImage: "arrow.clockwise")
                                }
                                .disabled(isLoadingGroqModels)
                                if let groqModelLoadError {
                                    Text(groqModelLoadError).font(.footnote).foregroundStyle(.red)
                                }
                                Text(appText("Активные чат-модели загружаются из API Groq с учётом сохранённого ключа.", "Active chat models are loaded from the Groq API using the saved key."))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else if store.selectedProvider == .llm7 {
                                Picker(appText("Модель · LLM7.io", "Model · LLM7.io"), selection: $store.selectedModelID) {
                                    Text("default · LLM7.io").tag("default")
                                    ForEach(llm7Models) { model in Text(model.id).tag(model.id) }
                                    if store.selectedModelID != "default", !llm7Models.contains(where: { $0.id == store.selectedModelID }) {
                                        Text("Custom · \(store.selectedModelID)").tag(store.selectedModelID)
                                    }
                                }
                                .pickerStyle(.menu)
                                Button {
                                    Task { await refreshLLM7Models() }
                                } label: {
                                    Label(isLoadingLLM7Models ? appText("Загружаю модели…", "Loading models…") : appText("Обновить список моделей", "Refresh model list"), systemImage: "arrow.clockwise")
                                }
                                .disabled(isLoadingLLM7Models)
                                if let llm7ModelLoadError {
                                    Text(llm7ModelLoadError).font(.footnote).foregroundStyle(.red)
                                }
                                Text(appText("Список загружается из каталога LLM7.io и содержит модели чата с OpenAI-совместимым API.", "Models are loaded from the LLM7.io catalog and filtered to chat models with the OpenAI-compatible API."))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker(appText("Модель · Pollinations.ai", "Model · Pollinations.ai"), selection: $store.selectedModelID) {
                                    ForEach(pollinationsModels) { model in
                                        Text(model.title).tag(model.id)
                                    }
                                    if !pollinationsModels.contains(where: { $0.id == store.selectedModelID }) {
                                        Text("Custom · \(store.selectedModelID)").tag(store.selectedModelID)
                                    }
                                }
                                .pickerStyle(.menu)
                                Button {
                                    guard Keychain.read("pollinations_api_key")?.isEmpty == false else {
                                        pollinationsModelLoadError = appText("Сначала сохрани API-ключ Pollinations.ai.", "Save a Pollinations.ai API key first.")
                                        return
                                    }
                                    Task { await refreshPollinationsModels() }
                                } label: {
                                    Label(isLoadingPollinationsModels ? appText("Загружаю модели…", "Loading models…") : appText("Обновить список моделей", "Refresh model list"), systemImage: "arrow.clockwise")
                                }
                                .disabled(isLoadingPollinationsModels)
                                if let pollinationsModelLoadError {
                                    Text(pollinationsModelLoadError).font(.footnote).foregroundStyle(.red)
                                }
                                Text(appText("Каталог загружается из Pollinations.ai и показывает текстовые чат-модели и их псевдонимы. По умолчанию выбрана модель openai.", "The Pollinations catalog shows text chat models and their aliases. The default model is openai."))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section {
                            TextField("provider/model-id", text: Binding(
                                get: {
                                    switch store.selectedProvider {
                                    case .groq: customModelID
                                    case .llm7: customLLM7ModelID
                                    case .pollinations: customPollinationsModelID
                                    }
                                },
                                set: { value in
                                    switch store.selectedProvider {
                                    case .groq: customModelID = value
                                    case .llm7: customLLM7ModelID = value
                                    case .pollinations: customPollinationsModelID = value
                                    }
                                }
                            ))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.body, design: .monospaced))

                            Button {
                                let modelID: String
                                switch store.selectedProvider {
                                case .groq: modelID = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                                case .llm7: modelID = customLLM7ModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                                case .pollinations: modelID = customPollinationsModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                                guard isValidGroqModelID(modelID) else {
                                    didApplyCustomModel = false
                                    customModelError = appText(
                                        "Введи точный ID модели: латинские буквы, цифры, точка, дефис, подчёркивание, / или :.",
                                        "Enter a valid model ID using letters, numbers, dot, dash, underscore, /, or :."
                                    )
                                    return
                                }
                                switch store.selectedProvider {
                                case .groq:
                                    customModelID = modelID
                                case .llm7:
                                    customLLM7ModelID = modelID
                                case .pollinations:
                                    customPollinationsModelID = modelID
                                }
                                store.selectedModelID = modelID
                                customModelError = nil
                                didApplyCustomModel = true
                            } label: {
                                Label(
                                    didApplyCustomModel ? appText("Модель выбрана", "Model selected") : appText("Использовать модель", "Use model"),
                                    systemImage: didApplyCustomModel ? "checkmark.circle.fill" : "checkmark"
                                )
                                .foregroundStyle(didApplyCustomModel ? .green : .cyan)
                            }
                            if let customModelError {
                                Text(customModelError).font(.footnote).foregroundStyle(.red)
                            }
                            Link(
                                appText("Открыть каталог моделей \(store.selectedProvider.title)", "Open \(store.selectedProvider.title) model catalog"),
                                destination: URL(string: {
                                    switch store.selectedProvider {
                                    case .groq: "https://console.groq.com/docs/models"
                                    case .llm7: "https://api.llm7.io/v1/models"
                                    case .pollinations: "https://gen.pollinations.ai/models"
                                    }
                                }())!
                            )
                        } header: {
                            Text(appText("Своя модель · \(store.selectedProvider.title)", "Custom model · \(store.selectedProvider.title)"))
                        } footer: {
                            Text(appText(
                                "Вставь точный model ID из каталога \(store.selectedProvider.title). Модель сохранится отдельно для выбранного провайдера.",
                                "Paste the exact model ID from the \(store.selectedProvider.title) catalog. It is saved for the selected provider."
                            ))
                        }

                        Section(appText("Распознавание речи", "Speech recognition")) {
                            Text(appText(
                                "Для Pro голосового режима используется системное распознавание iPhone, поэтому он работает независимо от выбранной чат-модели. Разреши Xi Lite доступ к микрофону и распознаванию речи в настройках iPhone.",
                                "Pro voice mode uses iPhone speech recognition, independent of the selected chat provider. Allow Xi Lite to access the microphone and Speech Recognition in iPhone Settings."
                            ))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            Button(appText("Открыть настройки Xi Lite", "Open Xi Lite Settings")) {
                                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                UIApplication.shared.open(url)
                            }
                        }

                        Section(appText("Другие бесплатные модели Groq", "Other free Groq models")) {
                            freeModelRow("meta-llama/llama-prompt-guard-2-22m", detail: appText("Обнаружение prompt injection", "Prompt-injection detection"))
                            freeModelRow("meta-llama/llama-prompt-guard-2-86m", detail: appText("Обнаружение prompt injection", "Prompt-injection detection"))
                            freeModelRow("whisper-large-v3", detail: appText("Речь → текст · мультиязычная", "Speech to text · multilingual"))
                            freeModelRow("whisper-large-v3-turbo", detail: appText("Быстрое распознавание речи", "Fast speech recognition"))
                            freeModelRow("canopylabs/orpheus-v1-english", detail: appText("Озвучивание · английский", "Text to speech · English"))
                            freeModelRow("canopylabs/orpheus-arabic-saudi", detail: appText("Озвучивание · арабский (Саудовская Аравия)", "Text to speech · Saudi Arabic"))
                            Text(appText(
                                "Это специализированные модели для аудио и безопасности, а не обычный чат. Свободный план и квоты Groq могут меняться.",
                                "These are specialized audio and safety models, not general chat models. Groq may change free-plan availability and quotas."
                            ))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }

                        Section {
                            SecureField(appText("Tavily API-ключ", "Tavily API key"), text: $searchAPIKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button {
                                let key = searchAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !key.isEmpty else {
                                    didSaveSearchKey = false
                                    searchKeySaveError = appText("Вставь бесплатный API-ключ Tavily.", "Enter your free Tavily API key.")
                                    return
                                }
                                do {
                                    try Keychain.save(key, account: "tavily_api_key")
                                    guard Keychain.read("tavily_api_key") == key else {
                                        throw ChatError.server(appText("Ключ поиска не найден после сохранения. Попробуй ещё раз.", "The search key could not be read after saving. Please try again."))
                                    }
                                    didSaveSearchKey = true
                                    searchKeySaveError = nil
                                } catch {
                                    didSaveSearchKey = false
                                    searchKeySaveError = error.localizedDescription
                                }
                            } label: {
                                Label(didSaveSearchKey ? appText("Ключ поиска сохранён", "Search key saved") : appText("Сохранить ключ поиска", "Save search key"), systemImage: didSaveSearchKey ? "checkmark.circle.fill" : "magnifyingglass")
                                    .foregroundStyle(didSaveSearchKey ? .green : .cyan)
                            }
                            if let searchKeySaveError {
                                Text(searchKeySaveError)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        } header: {
                            Text(appText("Поиск в интернете · Tavily", "Web search · Tavily"))
                        } footer: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(appText("Бесплатно: 1 000 поисковых кредитов в месяц, 1 кредит за обычный поиск. Банковская карта не нужна. Ключ хранится в Keychain.", "Free: 1,000 search credits per month, 1 credit per basic search. No payment card required. The key is stored in Keychain."))
                                Link(appText("Получить бесплатный ключ Tavily", "Get a free Tavily key"), destination: URL(string: "https://app.tavily.com")!)
                            }
                        }

                        Section {
                            HStack {
                                TextField(appText("Например: предпочитаю краткие ответы", "For example: I prefer concise answers"), text: $newMemory)
                                    .textInputAutocapitalization(.sentences)
                                Button {
                                    let value = newMemory.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !value.isEmpty else { return }
                                    store.memories.append(value)
                                    newMemory = ""
                                } label: {
                                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.cyan)
                                }
                                .disabled(newMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }

                            if store.memories.isEmpty {
                                Text(appText("Добавь факты и предпочтения — Xi Lite учтёт их в следующих ответах.", "Add facts and preferences for Xi Lite to remember in future replies."))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                ForEach(store.memories.indices, id: \.self) { index in
                                    HStack {
                                        Image(systemName: "brain.head.profile").foregroundStyle(.red)
                                        Text(store.memories[index])
                                        Spacer(minLength: 4)
                                        Button(role: .destructive) { store.memories.remove(at: index) } label: {
                                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text(appText("Память", "Memory"))
                        } footer: {
                            Text(appText("Память хранится только локально на этом устройстве. Удаляй записи в любой момент.", "Memory is stored only on this device. You can delete entries at any time."))
                        }

                        Section {
                            ZStack(alignment: .topLeading) {
                                if store.customSystemPrompt.isEmpty {
                                    Text(appText(
                                        "Например: отвечай кратко, используй списки и объясняй сложные термины простыми словами…",
                                        "For example: keep answers concise, use lists, and explain complex terms in simple language…"
                                    ))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 8)
                                }
                                TextEditor(text: $store.customSystemPrompt)
                                    .frame(minHeight: 120)
                                    .scrollContentBackground(.hidden)
                                    .tint(XiPalette.cyan)
                                    .accessibilityLabel(appText("Дополнительный system prompt", "Additional system prompt"))
                                    .disabled(!account.isPremium)
                            }
                                if !account.isPremium {
                                    Button(appText("Разблокировать System prompt в Pro", "Unlock System prompt with Pro")) { isProOfferPresented = true }
                                    .foregroundStyle(XiPalette.cyan)
                                }

                            if !store.customSystemPrompt.isEmpty {
                                Button(role: .destructive) {
                                    store.customSystemPrompt = ""
                                } label: {
                                    Label(appText("Очистить инструкции", "Clear instructions"), systemImage: "trash")
                                }
                            }
                        } header: {
                            Text("System prompt")
                        } footer: {
                            Text(appText(
                                "Эти инструкции добавляются к системному промпту Xi Lite и применяются ко всем новым ответам. Хранятся только на этом устройстве.",
                                "These instructions are appended to Xi Lite's system prompt and apply to all new replies. Stored only on this device."
                            ))
                        }

                        Section(appText("Голосовой режим · Бета", "Voice mode · Beta")) {
                            Label(appText("Бета-функция", "Beta feature"), systemImage: "flask")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(XiPalette.cyan)
                            Label(appText("Нажми микрофон, скажи фразу и нажми стоп для отправки.", "Tap the mic, speak, then tap stop to send."), systemImage: "mic.fill")
                            if !account.isPremium {
                                Button(appText("Голосовой режим со всеми провайдерами · Pro", "Voice mode with all providers · Pro")) { isProOfferPresented = true }
                                    .foregroundStyle(XiPalette.cyan)
                            }
                            Text(appText(
                                "Голосовой режим Pro работает с выбранным провайдером чата: речь распознаёт системная служба iPhone, выбранная модель формирует ответ, а iPhone озвучивает его. Отдельный Groq API-ключ для распознавания и озвучивания не требуется.",
                                "Pro voice mode works with the selected chat provider: iPhone speech recognition transcribes your voice, the selected model generates the reply, and iPhone reads it aloud. No separate Groq key is required for speech recognition or playback."
                            ))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }

                        Section(appText("Интерфейс", "Appearance")) {
                            Toggle(isOn: $isDarkTheme) {
                                Label(isDarkTheme ? appText("Тёмная тема", "Dark theme") : appText("Светлая тема", "Light theme"), systemImage: isDarkTheme ? "moon.fill" : "sun.max.fill")
                            }
                            .tint(XiPalette.cyan)
                            Picker(appText("Язык", "Language"), selection: $appLanguage) {
                                Text("Русский").tag("ru")
                                Text("English").tag("en")
                            }
                            .pickerStyle(.menu)
                            Label("Liquid Glass · iOS 26", systemImage: "sparkles").foregroundStyle(.primary)
                        }

                        Section {
                            HStack(spacing: 14) {
                                if let data = Data(base64Encoded: profileImageBase64), let image = UIImage(data: data) {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 54, height: 54).clipShape(Circle())
                                } else {
                                    Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().frame(width: 54, height: 54).foregroundStyle(XiPalette.gradient)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(account.accountName).font(.headline)
                                    Text(account.isPremium ? "Pro" : appText("Бесплатный аккаунт", "Free account"))
                                        .font(.caption).foregroundStyle(account.isPremium ? .green : .secondary)
                                }
                                Spacer()
                                PhotosPicker(selection: $selectedProfilePhoto, matching: .images) {
                                    Image(systemName: "camera.fill").foregroundStyle(.cyan)
                                }
                            }
                            TextField(appText("Новое имя", "New account name"), text: $editedAccountName)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button(appText("Сменить имя", "Change name")) {
                                Task {
                                    do {
                                        try await account.updateName(editedAccountName)
                                        editedAccountName = account.accountName
                                        accountActionMessage = appText("Имя изменено.", "Name updated.")
                                    } catch { accountActionMessage = error.localizedDescription }
                                }
                            }.disabled(editedAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            SecureField(appText("Текущий PIN-код", "Current PIN"), text: $currentPIN).keyboardType(.numberPad)
                            SecureField(appText("Новый PIN-код", "New PIN"), text: $newPIN).keyboardType(.numberPad)
                            Button(appText("Сменить PIN-код", "Change PIN")) {
                                Task {
                                    do {
                                        try await account.updatePIN(current: currentPIN, new: newPIN)
                                        currentPIN = ""
                                        newPIN = ""
                                        accountActionMessage = appText("PIN-код изменён.", "PIN updated.")
                                    } catch { accountActionMessage = error.localizedDescription }
                                }
                            }.disabled(currentPIN.isEmpty || newPIN.isEmpty)

                            if let accountActionMessage {
                                Text(accountActionMessage).font(.footnote).foregroundStyle(.secondary)
                            }
                            Button(role: .destructive) {
                                Task { await account.logout() }
                            } label: { Label(appText("Выйти из аккаунта", "Sign out"), systemImage: "rectangle.portrait.and.arrow.right") }
                        } header: {
                            Text(appText("Аккаунт", "Account"))
                        } footer: {
                            Text(appText("Аватар хранится только на устройстве. PIN-код и статус Pro проверяются сервером аккаунтов.", "Your avatar stays on this device. PIN and Pro status are managed by the account server."))
                        }

                        Section {
                            if account.isPremium {
                                Label(appText("Виджет Xi Lite доступен", "Xi Lite Home Screen widget is ready"), systemImage: "square.grid.2x2.fill")
                                Text(appText("Добавь его с экрана «Домой»: удерживай пустое место, нажми «+» и выбери Xi Lite.", "From Home Screen, touch and hold an empty area, tap +, then choose Xi Lite."))
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else {
                                Button(appText("Виджеты на экран «Домой» · Pro", "Home Screen widgets · Pro")) { isProOfferPresented = true }
                                    .foregroundStyle(XiPalette.cyan)
                            }
                            if account.isPremium {
                                PhotosPicker(selection: $selectedBackgroundPhoto, matching: .images) {
                                    Label(chatBackgroundPhotoBase64.isEmpty ? appText("Установить фото-фон", "Set a photo background") : appText("Заменить фото-фон", "Change photo background"), systemImage: "photo.on.rectangle.angled")
                                }
                                if !chatBackgroundPhotoBase64.isEmpty {
                                    Button(role: .destructive) {
                                        chatBackgroundPhotoBase64 = ""
                                    } label: {
                                        Label(appText("Убрать фото-фон", "Remove photo background"), systemImage: "trash")
                                    }
                                }
                            } else {
                                Button(appText("Своё фото на фон · Pro", "Use your photo as background · Pro")) { isProOfferPresented = true }
                                    .foregroundStyle(XiPalette.cyan)
                            }
                            Picker(appText("Цвет градиента", "Gradient colors"), selection: $gradientPalette) {
                                ForEach(XiPalette.gradientOptions, id: \.id) { option in
                                    Text(appText(option.titleRU, option.titleEN)).tag(option.id)
                                }
                                Text(appText("Своя тема…", "Custom theme…")).tag("custom")
                            }
                            .disabled(!account.isPremium)
                            if gradientPalette == "custom", account.isPremium {
                                ColorPicker(appText("Цвет 1", "Color 1"), selection: $themeColorOne, supportsOpacity: false)
                                ColorPicker(appText("Цвет 2", "Color 2"), selection: $themeColorTwo, supportsOpacity: false)
                                ColorPicker(appText("Цвет 3", "Color 3"), selection: $themeColorThree, supportsOpacity: false)
                                    .onChange(of: themeColorOne) { _, color in saveThemeColor(color, key: "customGradientColor1") }
                                    .onChange(of: themeColorTwo) { _, color in saveThemeColor(color, key: "customGradientColor2") }
                                    .onChange(of: themeColorThree) { _, color in saveThemeColor(color, key: "customGradientColor3") }
                            }
                            if !account.isPremium {
                                Button(appText("Темы и создание своей темы доступны в Pro", "Preset and custom themes are available with Pro")) { isProOfferPresented = true }
                                    .font(.footnote.weight(.semibold)).foregroundStyle(XiPalette.cyan)
                            }
                            Label(appText("Закрепляй важные чаты через контекстное меню чата.", "Pin important chats from a chat’s context menu."), systemImage: "pin.fill")
                                .font(.footnote).foregroundStyle(.secondary).opacity(account.isPremium ? 1 : 0.55)
                            Toggle(isOn: $autoSwitchProvider) {
                                Label(appText("Автосмена провайдера при лимите", "Auto-switch provider at limit"), systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                            }
                            .disabled(!account.isPremium)
                            Text(appText("Автосмена переключит чат на другой подключённый провайдер, если текущий вернёт ошибку лимита.", "Automatically retry with another configured provider if the current provider reports a quota limit."))
                                .font(.footnote).foregroundStyle(.secondary)
                                .opacity(account.isPremium ? 1 : 0.55)
                            Toggle(isOn: $localToolsEnabled) {
                                Label(appText("Использование инструментов", "Use tools"), systemImage: "wrench.and.screwdriver")
                            }
                            .disabled(!account.isPremium)
                            Text(appText(
                                "Только Pro. ИИ получает доступ к командам ios_system, включая Git через Dulwich, Python 3.9/pip, файловые, текстовые, архивные, сетевые и SSH-утилиты (base64, df, du, realpath и другие). Всё работает внутри папки XiLiteAI в iOS sandbox. Git CLI реализован не полностью; pip устанавливает только pure-Python wheels. Новые и изменённые файлы прикрепляются к ответу; ZIP собирается отдельным инструментом.",
                                "Pro only. The AI can use ios_system commands, including Git via Dulwich, Python 3.9/pip, file, text, archive, network, and SSH utilities (base64, df, du, realpath, and more). Everything runs inside XiLiteAI within the iOS sandbox. Git CLI coverage is partial; pip installs only pure-Python wheels. New/changed files attach to the reply; ZIP creation uses a dedicated tool."
                            ))
                                .font(.footnote).foregroundStyle(.secondary)
                                .opacity(account.isPremium ? 1 : 0.55)
                        } header: {
                            HStack {
                                Text(appText("Pro функции", "Pro features"))
                                Spacer()
                                if account.isPremium {
                                    Button(appText("Сравнить планы", "Compare plans")) { isPlanComparisonPresented = true }
                                        .font(.caption.weight(.semibold)).foregroundStyle(XiPalette.cyan)
                                } else {
                                    Button(appText("Получить Pro", "Get Pro")) { isProOfferPresented = true }
                                        .font(.caption.weight(.semibold)).foregroundStyle(XiPalette.cyan)
                                }
                            }
                        } footer: {
                            if !account.isPremium {
                                Text(appText("Функции Pro доступны после активации аккаунта на сервере.", "Pro features unlock when the account is upgraded on the server."))
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                .onAppear { if editedAccountName.isEmpty { editedAccountName = account.accountName } }
                .onAppear {
                    themeColorOne = Color(hex: UserDefaults.standard.string(forKey: "customGradientColor1") ?? "12F4FF")
                    themeColorTwo = Color(hex: UserDefaults.standard.string(forKey: "customGradientColor2") ?? "8C47FF")
                    themeColorThree = Color(hex: UserDefaults.standard.string(forKey: "customGradientColor3") ?? "FF315A")
                    if !account.isPremium && store.selectedProvider == .pollinations { store.selectedProvider = .groq }
                }
                .onChange(of: selectedProfilePhoto) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data),
                           let resized = image.jpegData(compressionQuality: 0.75) {
                            profileImageBase64 = resized.base64EncodedString()
                        }
                    }
                }
                .onChange(of: selectedBackgroundPhoto) { _, item in
                    guard let item else { return }
                    Task {
                        guard let data = try? await item.loadTransferable(type: Data.self),
                              let image = UIImage(data: data),
                              let resized = resizedJPEG(image), resized.count <= 4_000_000 else {
                            accountActionMessage = appText("Не удалось загрузить фото-фон.", "Could not load the background photo.")
                            return
                        }
                        chatBackgroundPhotoBase64 = resized.base64EncodedString()
                        accountActionMessage = nil
                    }
                }
                .task {
                    await account.refreshAccount()
                    await refreshGroqModels()
                    await refreshLLM7Models()
                    await refreshPollinationsModels()
                }
                .navigationTitle(appText("Настройки", "Settings"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(appText("Готово", "Done")) { dismiss() }.foregroundStyle(.cyan)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(uiColor: .systemBackground))
            .sheet(isPresented: $isProOfferPresented) { ProLockedView(feature: appText("Все возможности Pro", "All Pro features")) }
            .sheet(isPresented: $isPlanComparisonPresented) { PlanComparisonView() }
            .sheet(isPresented: $isLocalModelLibraryPresented) { LocalModelLibraryView().environmentObject(localModels) }
        }

    private func saveThemeColor(_ color: Color, key: String) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let hex = String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        UserDefaults.standard.set(hex, forKey: key)
        gradientPalette = "custom"
    }
}

extension View {
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self
                .background(XiPalette.gradient.opacity(0.08), in: shape)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    shape.strokeBorder(XiPalette.gradient.opacity(0.38), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
        } else {
            self
                .background(XiPalette.gradient.opacity(0.08), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(XiPalette.gradient.opacity(0.32), lineWidth: 1))
        }
    }
}

