# /slash

/slash is a Flutter app for shipping GitHub changes and watching live VPS runtime state from one place.

It combines AI-assisted repo work, branch-aware editing, project reporting, pull request review, and SSH-based ops tools in a single mobile-first interface.

## What The App Includes

- `Prompt`: repo-aware AI chat for planning changes, generating edits, and reviewing proposed diffs
- `Code`: manual editor with syntax highlighting, file browsing, quick open, AI side chat, pull-latest, and commit/push flows
- `Project`: repo health overview with summaries, risks, action items, contributors, timeline, and PDF export
- `Ops`: SSH-backed VPS tooling for connection setup, live metrics, Docker containers, `systemd` services, top processes, and terminal commands
- `PRs`: open pull request inbox with filters, repo scoping, search, detail views, comments, approvals, and change requests
- `Settings`: provider selection, model configuration, GitHub device-flow sign-in, and secure credential storage

## Current Product Flow

### Prompt

- Select a repository and branch
- Attach files manually or let /slash auto-discover likely relevant files
- Send a request for a change, explanation, or review
- Inspect the generated summary and draft before moving to deeper editing
- Approve a reviewed suggestion to open a new pull request automatically

### Code

- Browse the current branch and open files directly
- Use quick-open and recent files for faster navigation
- Edit manually in a syntax-highlighted editor
- Ask the assistant for targeted edits, explanations, or reviews on the open file
- Pull the latest remote file before pushing
- Commit and push changes to the selected branch

### Project

- Generate a repo overview for the last `24h` or `7d`
- See engineering and executive summaries
- Review highlights, risks, and next actions
- Inspect PR, issue, release, workflow, contributor, and timeline signals
- Preview or share a PDF executive summary

### Ops

- Save an SSH profile locally with password or private key auth
- Connect to a VPS and refresh telemetry
- View CPU, memory, disk, and container trends
- Inspect running Docker containers and `systemd` services
- Review top processes
- Run terminal commands against the saved host and keep recent command history

### PRs

- View open pull requests involving the authenticated user
- Filter by `all`, `author`, `assigned`, or `review_requested`
- Scope PRs to the currently selected repo
- Search by title/body query
- Open PR details, leave comments, approve, or request changes

## Authentication And Providers

- AI providers supported today: `OpenAI` and `OpenRouter`
- GitHub auth uses OAuth device flow
- Keys, models, GitHub session data, and VPS connection details are stored locally with `flutter_secure_storage`

## Setup

### Prerequisites

- Flutter SDK
- An OpenAI API key or OpenRouter API key
- A GitHub OAuth App client ID if you want GitHub sign-in enabled in your build
- For Ops: a reachable Linux host with SSH access

### Optional build-time configuration

You can bundle the GitHub client ID and set default model IDs at launch time:

```bash
flutter run \
  --dart-define=GITHUB_OAUTH_CLIENT_ID=your_client_id \
  --dart-define=OPENAI_MODEL=gpt-4o-mini \
  --dart-define=OPENROUTER_MODEL=openai/gpt-4o-mini
```

If you do not provide `GITHUB_OAUTH_CLIENT_ID`, GitHub sign-in UI will still render, but the app will explain that the current build is not configured for GitHub auth.

### Run locally

```bash
flutter pub get
flutter run
```

## Typical Workflow

1. Open `Settings` and choose `OpenAI` or `OpenRouter`
2. Save your API key and preferred model
3. Connect GitHub through device flow
4. Pick a repo and branch in `Prompt` or `Code`
5. Ask /slash for a change, or open a file and edit directly
6. Review the generated draft or diff
7. Commit and push from `Code`, or jump to `PRs` to review existing work
8. Use `Project` for repo health snapshots and `Ops` for live VPS inspection

## Notes

- Ops relies on live SSH sockets and is not available on Flutter Web
- Project export uses the `pdf` and `printing` packages
- Prompt-created pull requests use `slash/<timestamp>` branches
- The app defaults to `gpt-4o-mini` for OpenAI and `openai/gpt-4o-mini` for OpenRouter unless you override them

## License

MIT
