# AI Copilot Mapper

AI Copilot Mapper is a lightweight application written in PureBasic that lets you take control of the new physical Windows Copilot key on your keyboard. Instead of being locked to Microsoft's default, this program allows you to "remap" the key (F23 / Virtual Key $86) to open exactly the AI assistant you prefer.

The program runs discreetly in the background via the system tray, giving you full control over your AI experience.

## ✨ Features
* **Choose your favorite AI:** Supports Google Gemini, OpenAI ChatGPT, Anthropic Claude, DeepSeek, Perplexity AI, and Microsoft Copilot.
* **Dynamic browser selection:** Automatically detects the browsers installed on your PC so you can pick your preferred one.
* **Multilingual:** Built-in support for 6 languages (English, Danish, Spanish, French, Italian, and German).
* **Dynamic Languages:** Will now pick up new language files automatically. Add your own translation.
* **Auto-start:** Can easily be configured to start automatically with Windows.
* **Memory:** Saves your preferences locally in an `.ini` file.

There are some issues with certain antivirus programs not allowing the autostart to be written to registry.

## 🛠️ How to Compile (Source Code)

To build the program from the source code, you will need PureBasic. Follow these simple steps to create your own `.exe` file:

1. Download and install [PureBasic](https://www.purebasic.com/).
2. Clone or download this repository, and open the `.pb` file in the PureBasic editor.
3. **Important regarding the icon:** Make sure the path to the `.ico` file in the code (locate the line with `LoadImage`) points to the location where you saved the icon on your computer. Alternatively, you can modify the code to load the icon from the same directory as the executable.
4. Go to the top menu and select **Compiler -> Create Executable...**
5. Save the file as, for example, `AICopilotMapper.exe` in a folder of your choice.
6. Run the `.exe` file! A small icon will now appear in the system tray, where you can right-click and configure the program.

---
*Developed in PureBasic to give users back the freedom over their hardware.*
