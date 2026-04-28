# OpenGram

OpenGram is a macOS menu bar app that checks grammar, spelling, and clarity in the apps where you write. It works locally by default, with no account, subscription, telemetry, or cloud service required.

Use it in Notes, Mail, browsers, editors, chat apps, and other supported apps. Press a shortcut, review the suggestions, and apply the ones you want.

## What OpenGram Does

- Finds grammar, spelling, punctuation, and clarity issues.
- Shows inline underlines over text in supported macOS apps.
- Lets you click a suggestion to replace the text in place.
- Lets you add words to your personal dictionary.
- Can rewrite selected text in a different tone when a reachable LLM endpoint is available.
- Keeps grammar checking local by default.

## Requirements

- macOS 14 Sonoma or later.
- Accessibility permission, so OpenGram can read and update text in other apps.
- Optional: a local or cloud LLM provider for AI rewrite, tone, and rephrase suggestions.

## Install

1. Open the OpenGram app.
2. If macOS asks for permission, allow OpenGram to run.
3. Keep OpenGram in your Applications folder if you want it available every day.

For developer setup or source builds, see [CONTRIBUTING.md](CONTRIBUTING.md).

## First Launch

OpenGram will ask for Accessibility access. This permission is required because macOS does not let apps read or replace text in other apps without it.

To enable it manually:

1. Open System Settings.
2. Go to Privacy & Security.
3. Open Accessibility.
4. Turn on OpenGram.
5. Quit and reopen OpenGram if suggestions do not appear right away.

## Basic Use

OpenGram runs from the menu bar.

- `Ctrl+Shift+G`: check the current text field.
- Click an underline or suggestion card to review a correction.
- Click the replacement text to apply it.
- Click Dismiss to ignore a suggestion.
- Click Add to Dictionary when OpenGram flags a word you want to keep.

OpenGram also watches supported text fields while you type and refreshes suggestions after a short pause.

## Rewrite Selected Text

Use `Ctrl+Shift+R` to rewrite selected text.

1. Select text in a supported app.
2. Press `Ctrl+Shift+R`.
3. Choose a tone, such as Friendly.
4. Review the revised text.
5. Click Replace to write it back into the original app.

Rewrite requires a reachable LLM provider. If rewrite does not respond, open Settings from the menu bar, check the endpoint, and click Test Connection.

## Settings

Open the menu bar icon and choose Settings.

### LLM Provider

Configure an OpenAI-compatible endpoint for AI-powered tone, rephrase, and rewrite features. The default endpoint points to a local server on your Mac.

Common local endpoint:

```text
http://localhost:1234/v1
```

Use the API Key field only if your provider requires one. API keys are stored in the macOS Keychain.

### Clarity

Turn clarity suggestions on or off. Subjective clarity suggestions are off by default to reduce noise.

### Whitelisted Apps

OpenGram only activates in apps on its whitelist. The default list includes common Apple apps, browsers, Microsoft Office apps, chat apps, and writing tools. Add the current app from Settings if OpenGram does not activate where you are writing.

### Advanced

Advanced settings control when AI suggestions are requested. Most users should leave these at their defaults.

## Privacy

OpenGram is local by default.

- Grammar, spelling, punctuation, dictionary, and clarity checks run on your Mac.
- OpenGram does not include telemetry, analytics, crash reporting, or an account system.
- API keys are stored in Keychain.
- AI features use the endpoint shown in Settings. The default endpoint is local: `http://localhost:1234/v1`.
- If that endpoint points to a cloud LLM provider, that provider may receive text needed for AI suggestions or rewrites.

## Troubleshooting

### The shortcut does nothing

Make sure OpenGram has Accessibility permission, then quit and reopen the app.

### Suggestions do not appear in an app

Open Settings, go to Whitelisted Apps, and add the current app. Some apps expose limited text information to macOS Accessibility, so OpenGram may work better in some apps than others.

### Rewrite says to select text first

Select the text you want to rewrite, then press `Ctrl+Shift+R` again.

### LLM features do not work

Open Settings, check the endpoint URL, model name, and API key, then click Test Connection. Local model servers need to be running before OpenGram can connect.

## Learn More

- [CONTRIBUTING.md](CONTRIBUTING.md): developer setup and contribution notes.
- [THIRD_PARTY.md](THIRD_PARTY.md): bundled third-party license information.
