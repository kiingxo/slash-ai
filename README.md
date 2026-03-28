# /slash: Pocket Engineer For GitHub

/slash is a Flutter app for browsing repos, planning edits, rewriting files with AI, reviewing diffs, and pushing changes from one place.

## What Changed

- Gemini has been removed from the product flow.
- AI providers are now `OpenAI` and `OpenRouter`.
- GitHub uses sign-in via OAuth device flow instead of asking for a personal access token.
- The editor now protects pushes with the file SHA it originally loaded, so stale remote changes are less likely to be overwritten accidentally.
- Prompt mode can auto-discover likely relevant files in the repo when you do not manually attach context.

## Features

- `OpenAI` or `OpenRouter` provider selection
- GitHub device-flow sign-in
- Repo browser with branch selection
- AI prompt-to-review flow
- Manual code editor with in-editor AI help
- Pull-latest before push from the editor
- PR creation and PR review tools
- Secure local credential storage

## Setup

### Prerequisites

- Flutter SDK
- An OpenAI API key or OpenRouter API key
- A GitHub OAuth App client ID

### Optional bundled GitHub OAuth client ID

You can bundle the client ID at build time:

```bash
flutter run --dart-define=GITHUB_OAUTH_CLIENT_ID=your_client_id
```

You can also set default models at build time:

```bash
flutter run \
  --dart-define=OPENAI_MODEL=gpt-4o-mini \
  --dart-define=OPENROUTER_MODEL=openai/gpt-4o-mini
```

### Run

```bash
flutter pub get
flutter run
```

## Workflow

1. Choose `OpenAI` or `OpenRouter`
2. Add the provider key and preferred model
3. Sign in with GitHub
4. Pick a repo and branch
5. Ask for a change or attach files directly
6. Review the generated diff
7. Open a PR or continue editing in the code screen
8. Pull latest before pushing if you want to refresh the remote file first

## Notes

- GitHub auth is stored locally on-device.
- PR branches are created as `slash/<timestamp>`.
- The prompt flow now tries to infer relevant files from the repo tree when no context is attached manually.

## License

MIT
