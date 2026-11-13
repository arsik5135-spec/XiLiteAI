# Xi Lite AI

Native SwiftUI iPhone chat app for iOS 26, inspired by the supplied chat screenshots. Includes Groq free-tier chat models (GPT-OSS 120B/20B, Qwen 3.8 27B, and the specialized GPT-OSS Safeguard 20B), selectable Russian Whisper V3/V3 Turbo transcription, Groq Orpheus English speech output, tap-to-send examples, local chat history and memory, Tavily search, structured Markdown responses, Liquid Glass, and persistent light/dark themes.

## Open and run

1. Open `XiLiteAI.xcodeproj` in Xcode 26 or later.
2. Select an iPhone simulator (or connected iPhone) running iOS 26 and run the `XiLiteAI` scheme.
3. Open Settings in the app and save a Groq API key. The key is stored in the iOS Keychain and is not committed to the project. Select a chat model in Settings or enter a custom Groq model ID from the model catalog.
4. To enable web search, create a [free Tavily account](https://app.tavily.com), then add its API key in Settings. Its free tier includes 1,000 basic searches per month and does not require a payment card. The Groq API key is still needed for AI answers.

For a physical iPhone, select your Apple development team under Signing & Capabilities.

## Account server and Pro access

The app uses a small Node.js account service for registration, PIN sign-in, and premium status. Start it from the project folder with `node server/server.js`; it listens on port 3000 and creates `server/accounts.json` on the first registration. No npm packages are required. In JustRunMy.App's shell, grant/revoke Pro with `npm --prefix server run premium -- give <accountName>` and `npm --prefix server run premium -- remove <accountName>`; list accounts with `npm --prefix server run premium -- accounts`. These shell commands update `accounts.json` atomically, and the running API reloads changes automatically. In an attached interactive server prompt, the shorter `premium give <accountName>` and `premium remove <accountName>` commands are also available. PINs are salted and hashed, and sessions expire after one week.

The account-server URL is configured in `AccountServerConfiguration.baseURL` in the app source and is not shown in the login UI. Account records are ignored by Git.

Free accounts can create up to 10 chats. Pro unlocks unlimited chats, gradient presets, automatic provider fallback on quota errors, and the tabbed Google browser. Chat history and profile photos remain local. The Pro link is configured in the app.

Conversation history and memory are stored locally with `UserDefaults`. Assistant responses render headings, paragraphs, numbered steps, bullets, and code blocks. Voice input uses multilingual Groq Whisper; Large V3 is the accuracy-focused Russian option and Turbo is faster. English speech output uses Groq Orpheus; Russian speech output uses the device's Russian voice because Groq's listed Orpheus voices support English and Saudi Arabic.

## Python in the local terminal

The local terminal includes Python 3.9 and can install packages from PyPI with `pip install package-name`; pip is bootstrapped from the bundled wheels the first time it is used. Installed packages are saved in the XiLiteAI workspace and can be imported by later Python commands. Because this is an iOS Python runtime without a compiler or arbitrary native extensions, only universal pure-Python wheels are supported. Packages that require C extensions or source builds cannot be installed.

## Git and terminal commands

The terminal provides `git` through the pure-Python Dulwich implementation, installed on first use. Common local Git commands include `init`, `status`, `add`, `commit`, `log`, `diff`, `branch`, and `checkout`; remote clone/fetch/pull/push commands are also available where supported by Dulwich. This is not a complete replacement for the system Git CLI. Configure the commit identity once with `git config --global user.name "Your Name"` and `git config --global user.email "you@example.com"`; these settings stay in the app workspace. Additional utilities include `base64`, `basename`, `dirname`, `realpath`, `df`, `du`, `less`, and `sleep`, alongside existing file, text, archive, curl, SSH, and network commands. All terminal operations remain restricted to the XiLiteAI workspace by the iOS sandbox.

## On-device GGUF models

Settings → **Local models · GGUF** lets you import a `.gguf` file from Files or find and download a GGUF file directly from a Hugging Face repository. Split GGUF models are supported: select all shards when importing from Files, or choose any shard in the Hugging Face list to download the complete set. Public repositories need no credentials; an optional Hugging Face token is kept in Keychain for gated repositories. Models are copied into the app's Documents storage and remain on-device. Enable **Use on-device model** to answer with the selected model; while enabled, chat prompts are not sent to cloud inference providers or uploaded to the account chat log. Local inference currently supports text only and uses a 4K context; choose a quantized model small enough for the iPhone's available memory, and review its Hugging Face license before use.

The local runtime is pinned to [swift-llama-cpp](https://github.com/pgorzelany/swift-llama-cpp) and llama.cpp. For iOS device builds, resolve Swift packages normally. The upstream llama.cpp XCFramework no longer includes Simulator slices; before building for an iOS Simulator, run `bash scripts/prepare-gguf-simulator.sh` once. This uses Xcode, CMake, and Git to build the simulator slice into SwiftPM's DerivedData checkout; the generated framework is not added to the app repository.
