# /slash: AI-Powered GitHub Mobile Assistant

![Built by BlueprintLabs](https://img.shields.io/badge/built%20by-BlueprintLabs-0057ff?style=flat-square)

ð¤ A beautiful, mobile-first Flutter app for managing GitHub repos, powered by Google Gemini and OpenAI.

## Overview

/slash is a mobile coding assistant for GitHub. It lets you securely connect your GitHub account and OpenAI/Gemini API keys, browse files, create branches, commit changes, open PRs, and review AI-generated code suggestionsâall from your phone, with a modern, dark-themed UI.

## Features

- ð± **Mobile-First UI**: Modern, dark, and responsive design
- ð **Secure Local Storage**: API keys and tokens stored securely on device
- ð§  **AI-Powered Code Suggestions**: Uses Gemini or OpenAI for code changes and PR summaries
- ðï¸ **File Browser**: Browse, view, and edit files in your GitHub repos
- ð¿ **Branching & PRs**: Create branches, commit changes, and open pull requests
- ð **Review & Approve**: Review diffs, summaries, and approve or reject AI changes
- ð **No Backend Required**: All logic runs on-device; no server needed

## Repository Structure

```
slash_flutter/
âââ lib/
â   âââ common/           # Shared providers, services, widgets
â   âââ features/         # Feature modules (auth, repo, file_browser, review, etc.)
â   âââ services/         # API service classes (GitHub, Gemini, Secure Storage)
â   âââ ui/               # UI components, theme, colors
â   âââ main.dart         # App entry point
âââ android/              # Android project files
âââ ios/                  # iOS project files
âââ pubspec.yaml          # Flutter dependencies
âââ README.md             # This file
```

## Setup Instructions

### 1. Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- A GitHub Personal Access Token (PAT)
- A Gemini or OpenAI API key

### 2. Clone & Install

```bash
git clone https://github.com/your-org/slash_flutter.git
cd slash_flutter
flutter pub get
```

### 3. Run the App

```bash
flutter run
```

### 4. Connect APIs

- On first launch, enter your Gemini/OpenAI API key and GitHub PAT in the app's onboarding screen.
- Your credentials are stored securely on your device.

## Configuration

- **Theme**: Dark mode by default, with vibrant purple and black
- **API Keys**: Managed via secure local storage
- **No backend**: All logic is client-side

## Output & Workflow

- **Prompt-to-PR**: Enter a prompt, review AI-generated code changes, and open a PRâall in-app
- **Review Screen**: See a diff, summary, and approve or reject changes
- **Branching**: PRs are created on new branches named `slash/<timestamp>`

## Example Workflow

1. Connect your APIs
2. Select a repo
3. Enter a prompt (e.g., "Add dark mode toggle")
4. Review the AI's suggestion and diff
5. Approve to create a branch, commit, and open a PR

## Troubleshooting

- **API Errors**: Ensure your keys are valid and have the correct scopes
- **GitHub PAT**: Needs `repo` scope for private repos
- **Gemini/OpenAI Key**: Must have sufficient quota

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Support

For issues and questions:
- Open an issue in this repository
- Check the troubleshooting section above

---

![Built by BlueprintLabs](https://img.shields.io/badge/built%20by-BlueprintLabs-0057ff?style=flat-square)

*Empowering AI developers with mobile