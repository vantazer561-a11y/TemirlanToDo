# Temirlan To Do AI Assistant Design

## Summary

Temirlan To Do will add an AI Assistant for personal use. The assistant will call Fireworks directly from the iOS app. The Fireworks API key will not be committed to the repository or hard-coded in source files. The user will enter the key inside the app, and the app will store it in iOS Keychain.

The assistant will help turn natural language into actionable tasks, break large tasks into smaller steps, improve task wording, and suggest a daily plan from existing tasks.

## Goals

- Add a personal AI Assistant screen to the app.
- Store the Fireworks API key securely in Keychain.
- Use Fireworks OpenAI-compatible Chat Completions API from Swift with `URLSession`.
- Send current task context and the user's assistant request to Fireworks.
- Parse structured JSON suggestions from the model.
- Show suggested changes before applying them.
- Apply task changes only after explicit user confirmation.

## Non-Goals

- No backend server for version 1.
- No shared accounts, login, subscriptions, or multi-user usage.
- No automatic task mutation without user confirmation.
- No voice assistant in version 1.
- No image generation inside the todo app.

## User Experience

The app will include an AI Assistant entry point from the main navigation. If no API key is saved, the screen will show a setup state with a secure text field, a short explanation, and a link to the Fireworks API keys page.

After setup, the assistant screen will show:

- A prompt input field.
- Quick action buttons:
  - Break task into steps.
  - Plan my day.
  - Create tasks from text.
  - Improve task wording.
- A response area with the assistant message.
- A preview list of suggested task changes.
- Apply and discard buttons.

The assistant should feel integrated with the existing cyberpunk productivity style: dark panels, neon cyan action highlights, magenta for important suggestions, and compact iOS-native controls.

## Assistant Capabilities

Version 1 will support these suggestion types:

- `create_task`: create a new task with title, notes, importance, My Day flag, and optional due date.
- `update_task`: update an existing task title, notes, importance, My Day flag, completion, or due date.
- `delete_task`: suggest deletion, but require explicit confirmation.
- `message_only`: return guidance without changing tasks.

For safety and user control, every action is previewed before it is applied.

## Architecture

New files:

- `TemirlanToDo/AI/KeychainStore.swift`: small wrapper for saving, loading, and deleting the Fireworks API key.
- `TemirlanToDo/AI/FireworksClient.swift`: URLSession client for the Fireworks Chat Completions API.
- `TemirlanToDo/AI/AssistantModels.swift`: request and response DTOs for assistant suggestions.
- `TemirlanToDo/AI/AssistantService.swift`: builds prompts from tasks, calls `FireworksClient`, and decodes structured output.
- `TemirlanToDo/Views/AssistantView.swift`: main assistant UI.
- `TemirlanToDo/Views/AISettingsView.swift`: API key setup and deletion UI.

Modified files:

- `TemirlanToDo/Views/RootView.swift`: add AI Assistant navigation entry.
- `TemirlanToDo/Stores/TaskStore.swift`: add methods for applying assistant suggestions.
- `TemirlanToDo.xcodeproj/project.pbxproj`: include new Swift files.

## Fireworks API

The app will call:

`https://api.fireworks.ai/inference/v1/chat/completions`

The request will use:

- Authorization header: `Bearer <Fireworks key from Keychain>`.
- JSON request body.
- Model: `accounts/fireworks/routers/kimi-k2p6-turbo`.
- Response format: JSON object, with prompt-enforced structured fields so the app can decode suggestions reliably.

The assistant prompt will instruct the model to act only as a productivity helper for the user's tasks. It should avoid pretending that suggested actions have already been applied.

## Data Flow

1. User enters or saves a Fireworks API key in the settings screen.
2. User opens AI Assistant and enters a request.
3. `AssistantService` collects relevant tasks from `TaskStore`.
4. `FireworksClient` sends the prompt and task context to Fireworks.
5. The response is decoded into `AssistantResponse`.
6. The app shows a preview of proposed actions.
7. User taps Apply.
8. `TaskStore` applies the confirmed actions and saves tasks to JSON storage.

## Error Handling

- If no API key exists, show setup UI.
- If the API key is invalid, show a clear authentication error and let the user replace the key.
- If the network is unavailable, show a retryable network error.
- If Fireworks returns malformed or unsupported JSON, show the assistant message as text and do not apply actions.
- If saving tasks fails after applying suggestions, keep the existing storage alert behavior.

## Security Notes

The API key is stored in iOS Keychain, not in the repository. This is acceptable for personal sideloaded use, but it is not the recommended architecture for a public app because a determined attacker may still inspect client behavior. A backend server remains the better option for public distribution.

The app should never log the API key, display it after saving, or include it in crash/error messages.

## Testing

Unit tests should cover:

- Keychain wrapper behavior through an injectable test store where practical.
- Decoding assistant structured JSON.
- Applying `create_task`, `update_task`, `delete_task`, and `message_only` actions.
- Handling invalid/missing API key states without mutating tasks.

Manual verification should cover:

- Saving and deleting an API key.
- Sending a request with a valid key.
- Seeing suggestions before applying.
- Applying suggestions and confirming tasks persist after app restart.
