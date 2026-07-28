# AI Copilot Mapper

AI Copilot Mapper is a lightweight application written in PureBasic that lets you take control of the new physical Windows Copilot key on your keyboard. Instead of being locked to Microsoft's default, this program allows you to "remap" the key (F23 / Virtual Key $86) to open exactly the AI assistant you prefer.

The program runs discreetly in the background via the system tray, giving you full control over your AI experience.

## ✨ Features
* **Embedded Native View (New!):** Experience a fast, integrated UI powered by Edge WebView2. It keeps your AI sessions (cookies/logins) separate from your main browser for a seamless, app-like experience.
* **In-App Quick Switcher:** Instantly switch between AI models via a sleek dropdown menu directly within the embedded view.
* **Choose your favorite AI:** Built-in support for Google Gemini, OpenAI ChatGPT, Anthropic Claude, DeepSeek, Perplexity AI, and Microsoft Copilot.
* **Custom AI Support:** Add your own custom URLs, including local instances like Open WebUI (e.g., `http://localhost:3000`).
* **Per-App Profiles:** Automatically change the remapper's behavior based on the active foreground application (e.g., pause the hook while gaming, or switch to a coding AI when your IDE is open).
* **Alternative Key Modes:** Don't want an AI? Remap the Copilot key to function as Right-CTRL or Right-ALT instead.
* **Dynamic browser selection:** If you prefer using an external browser over the embedded view, it automatically detects installed browsers on your PC so you can pick your preferred one.
* **Multilingual:** Built-in support for multiple languages (English, Danish, Spanish, French, Italian, and German). Simply drop a new `.lng` file in the directory to add a translation dynamically.
* **Auto-start & Memory:** Can easily be configured to start with Windows and saves all your preferences locally in a lightweight `.ini` file.

*Note: There are some known issues with certain antivirus programs preventing the auto-start registry key from being written.*

## 🛠️ How to Compile (Source Code)

To build the program from the source code, you will need PureBasic. Follow these simple steps to create your own standalone `.exe` file:

1. Download and install [PureBasic](https://www.purebasic.com/).
2. Clone or download this repository.
3. Ensure the `aicopilotmapper.ico` file is located in the same folder as the source code (the compiler uses `IncludeBinary` to embed it directly into the `.exe`).
4. Open the `.pb` file in the PureBasic editor.
5. Go to the top menu and select **Compiler -> Create Executable...**
6. Save the file as `AICopilotMapper.exe` in a folder of your choice.
7. Run the `.exe` file! A small icon will now appear in the system tray, where you can right-click and configure the program.

---
*Developed in PureBasic to give users back the freedom over their hardware.*
