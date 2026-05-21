# Temirlan To Do Design

## Summary

Temirlan To Do is a native iOS 15+ task manager inspired by Microsoft To Do. The first version will be built with SwiftUI and local JSON file storage. It will focus on fast everyday task capture, clean task organization, and a modern iOS interface with a restrained cyberpunk visual identity.

The app will be prepared for GitHub-based builds. The repository will include an Xcode project and a GitHub Actions workflow that runs `xcodebuild`. Signed IPA export will be documented and wired for Apple Developer secrets.

## Goals

- Build a working iOS 15+ SwiftUI app named Temirlan To Do.
- Support local task persistence without Core Data.
- Provide core To Do flows: create, edit, complete, delete, search, mark important, and assign due dates.
- Include smart views: My Day, Important, Planned, and Tasks.
- Use a modern cyberpunk-inspired design while keeping the app practical and readable.
- Add GitHub Actions configuration for CI builds and future signed IPA export.

## Non-Goals

- No iCloud sync in version 1.
- No user accounts, collaboration, reminders, or push notifications in version 1.
- No Core Data in version 1.
- No Android or web version.

## Product Design

The first screen will show the main task groups:

- My Day: tasks explicitly added to today or due today.
- Important: tasks marked with a star.
- Planned: tasks with due dates.
- Tasks: all active tasks.

Selecting a group opens a task list. Users can add a task from a bottom composer that stays close to the thumb area, complete tasks with a checkbox-style control, mark tasks as important, and open a detail sheet to edit title, notes, due date, My Day visibility, and completion state.

Search will filter tasks by title and notes. Completed tasks remain visible in a collapsed completed section so users can recover from accidental completion without cluttering the active list.

## Visual Direction

The style should feel like a modern productivity app with cyberpunk accents:

- Dark mode first, but fully compatible with light mode.
- Deep charcoal backgrounds, electric cyan and magenta accents, and subtle glass-like panels.
- SF Symbols for familiar iOS actions.
- Crisp typography using system fonts.
- Rounded surfaces with controlled radius, avoiding oversized decorative cards.
- Neon accents used for focus states, selected navigation items, important tasks, and primary buttons.

The interface must remain calm enough for daily productivity. Cyberpunk styling should be atmospheric and polished, not noisy.

## Architecture

The app will use a small SwiftUI architecture:

- `TemirlanToDoApp`: app entry point.
- `TaskStore`: observable state container responsible for loading, saving, and mutating tasks.
- `TaskStorage`: JSON file persistence in Application Support.
- `TaskItem`: codable task model.
- `TaskListKind`: enum for smart lists and filtering.
- SwiftUI views split by responsibility:
  - Root navigation view.
  - Sidebar/list selector.
  - Task list screen.
  - Task row.
  - Add task composer.
  - Task detail editor.
  - Shared cyberpunk theme helpers.

The store owns task mutations, and views call store methods instead of editing persistence directly.

## Data Model

Each task will include:

- `id`: stable UUID.
- `title`: required string.
- `notes`: optional string.
- `isCompleted`: boolean.
- `isImportant`: boolean.
- `createdAt`: date.
- `updatedAt`: date.
- `dueDate`: optional date.
- `isInMyDay`: boolean.

The JSON file will store an array of tasks. Save operations will write atomically where practical.

## Error Handling

If loading fails, the app starts with an empty task list and keeps the error available for UI display. If saving fails, the app should show a lightweight alert so the user knows changes may not be persisted.

Malformed JSON should not crash the app. The storage layer should isolate decoding failures and report them through `TaskStore`.

## GitHub Build

The repository will include a GitHub Actions workflow for macOS:

- Checkout repository.
- Select available Xcode.
- Build the iOS app with `xcodebuild`.
- Run tests if a test target exists.

For signed IPA export, the workflow will be structured so these secrets can be added later:

- Apple signing certificate.
- Certificate password.
- Provisioning profile.
- Apple Team ID.
- Bundle identifier.

The initial workflow will support unsigned simulator builds immediately. Signed IPA export will be included as a documented optional workflow path that becomes active after Apple Developer signing secrets are added.

## Testing

Version 1 should include focused tests for:

- Task filtering for My Day, Important, Planned, and Tasks.
- Task creation, editing, completion, and deletion in `TaskStore`.
- JSON storage encode/decode behavior.

Manual verification should include launching the app in an iOS simulator, creating tasks, quitting/reopening, and confirming persistence.

## Scope For Implementation Plan

The implementation plan should create the Xcode project, add the SwiftUI app structure, implement the local JSON storage, build the main screens, add tests, and add GitHub Actions build configuration.
