# AI Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a personal Fireworks-powered AI Assistant to Temirlan To Do that stores the API key in Keychain and previews task changes before applying them.

**Architecture:** The iOS app calls Fireworks OpenAI-compatible Chat Completions API directly through `FireworksClient`. `AssistantService` converts current tasks into context and decodes structured JSON into `AssistantResponse`; `TaskStore` applies confirmed assistant actions.

**Tech Stack:** Swift 5, SwiftUI, URLSession, iOS Keychain via Security, XCTest, Fireworks Chat Completions API.

---

## Files

- Create `TemirlanToDo/AI/AssistantModels.swift`: assistant actions, DTOs, JSON schema, response decoding.
- Create `TemirlanToDo/AI/FireworksClient.swift`: URLSession-based Fireworks Chat Completions API client.
- Create `TemirlanToDo/AI/AssistantService.swift`: prompt construction and assistant orchestration.
- Create `TemirlanToDo/AI/KeychainStore.swift`: save/load/delete Fireworks API key.
- Create `TemirlanToDo/Views/AssistantView.swift`: assistant prompt, quick actions, preview/apply UI.
- Create `TemirlanToDo/Views/AISettingsView.swift`: API key setup screen.
- Modify `TemirlanToDo/Stores/TaskStore.swift`: apply assistant actions.
- Modify `TemirlanToDo/Views/RootView.swift`: navigation entry.
- Modify `TemirlanToDo.xcodeproj/project.pbxproj`: include new files.
- Create `TemirlanToDoTests/AssistantModelsTests.swift`.
- Create `TemirlanToDoTests/AssistantActionsTests.swift`.
- Modify `README.md`: direct API key and Sideloadly notes.

## Tasks

- [ ] Add tests for assistant JSON decoding and task action application.
- [ ] Implement assistant models and `TaskStore.applyAssistantActions`.
- [ ] Implement Keychain storage and Fireworks client.
- [ ] Implement Assistant service prompt/schema.
- [ ] Build SwiftUI settings and assistant screens.
- [ ] Wire files into the Xcode project.
- [ ] Update README.
- [ ] Verify file structure, JSON files, git status, and note that `xcodebuild` runs on GitHub Actions.

## Self-Review

- Covers the approved spec: direct Fireworks API, Keychain, structured output, preview before apply, and manual confirmation.
- No backend is introduced.
- No API key appears in code, docs examples, tests, or repo config.
