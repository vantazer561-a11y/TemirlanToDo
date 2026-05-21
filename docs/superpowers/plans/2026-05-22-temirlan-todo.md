# Temirlan To Do Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native iOS 15+ SwiftUI app named Temirlan To Do with local JSON task persistence and GitHub Actions build support.

**Architecture:** The app uses a small MV-style SwiftUI structure. `TaskStore` owns state and mutations, `TaskStorage` owns JSON persistence, and views filter through `TaskListKind`.

**Tech Stack:** Swift 5, SwiftUI, XCTest, JSON file storage in Application Support, Xcode project, GitHub Actions macOS runner.

---

## File Structure

- Create `TemirlanToDo.xcodeproj/project.pbxproj`: Xcode project with app and test targets.
- Create `TemirlanToDo/TemirlanToDoApp.swift`: app entry point.
- Create `TemirlanToDo/Models/TaskItem.swift`: codable task model.
- Create `TemirlanToDo/Models/TaskListKind.swift`: smart-list enum and filtering metadata.
- Create `TemirlanToDo/Storage/TaskStorage.swift`: atomic JSON persistence.
- Create `TemirlanToDo/Stores/TaskStore.swift`: observable state and task mutations.
- Create `TemirlanToDo/Theme/CyberpunkTheme.swift`: reusable colors and UI styling helpers.
- Create `TemirlanToDo/Views/RootView.swift`: navigation shell.
- Create `TemirlanToDo/Views/TaskListView.swift`: task list screen and search.
- Create `TemirlanToDo/Views/TaskRowView.swift`: task row.
- Create `TemirlanToDo/Views/AddTaskComposerView.swift`: bottom task composer.
- Create `TemirlanToDo/Views/TaskDetailView.swift`: task editor sheet.
- Create `TemirlanToDoTests/TaskStoreTests.swift`: store and filtering tests.
- Create `TemirlanToDoTests/TaskStorageTests.swift`: JSON persistence tests.
- Create `.github/workflows/ios-build.yml`: GitHub simulator build workflow with documented signed IPA path.
- Create `README.md`: project overview and GitHub signing notes.

## Task 1: Project Skeleton

**Files:**
- Create: `TemirlanToDo.xcodeproj/project.pbxproj`
- Create: `TemirlanToDo/Info.plist`
- Create: `TemirlanToDoTests/Info.plist`

- [ ] **Step 1: Create Xcode project**

Create an iOS app target named `TemirlanToDo` and a unit test target named `TemirlanToDoTests`. The app target uses bundle id `com.temirlan.todo`, deployment target `15.0`, SwiftUI lifecycle, and manual signing disabled for simulator CI.

- [ ] **Step 2: Verify project is discoverable**

Run: `Test-Path 'TemirlanToDo.xcodeproj/project.pbxproj'`
Expected: `True`

- [ ] **Step 3: Commit**

Run:

```powershell
git add TemirlanToDo.xcodeproj TemirlanToDo TemirlanToDoTests
git commit -m "chore: scaffold iOS project"
```

## Task 2: Models

**Files:**
- Create: `TemirlanToDo/Models/TaskItem.swift`
- Create: `TemirlanToDo/Models/TaskListKind.swift`

- [ ] **Step 1: Add task model**

Create `TaskItem` as `Identifiable`, `Codable`, `Equatable`, with `id`, `title`, `notes`, `isCompleted`, `isImportant`, `createdAt`, `updatedAt`, `dueDate`, and `isInMyDay`.

- [ ] **Step 2: Add smart-list enum**

Create `TaskListKind` cases: `myDay`, `important`, `planned`, `tasks`. Add title, subtitle, SF Symbol name, accent color name, and filtering methods.

- [ ] **Step 3: Commit**

Run:

```powershell
git add TemirlanToDo/Models
git commit -m "feat: add task models"
```

## Task 3: Storage And Store

**Files:**
- Create: `TemirlanToDo/Storage/TaskStorage.swift`
- Create: `TemirlanToDo/Stores/TaskStore.swift`
- Create: `TemirlanToDoTests/TaskStoreTests.swift`
- Create: `TemirlanToDoTests/TaskStorageTests.swift`

- [ ] **Step 1: Write focused tests**

Add XCTest coverage for creating, editing, completing, deleting, filtering My Day, Important, Planned, Tasks, and saving/loading JSON through a temporary file.

- [ ] **Step 2: Implement JSON storage**

Implement `TaskStorage` with `loadTasks()` and `saveTasks(_:)`. Use `JSONEncoder`, `JSONDecoder`, `.iso8601` date strategy, create the Application Support directory when needed, and write data atomically.

- [ ] **Step 3: Implement observable store**

Implement `TaskStore` as `ObservableObject` with published `tasks`, `lastErrorMessage`, and methods `addTask`, `updateTask`, `deleteTask`, `toggleCompletion`, `toggleImportance`, `tasks(for:calendar:)`, and `save()`.

- [ ] **Step 4: Commit**

Run:

```powershell
git add TemirlanToDo/Storage TemirlanToDo/Stores TemirlanToDoTests
git commit -m "feat: add local task persistence"
```

## Task 4: SwiftUI App

**Files:**
- Create: `TemirlanToDo/TemirlanToDoApp.swift`
- Create: `TemirlanToDo/Theme/CyberpunkTheme.swift`
- Create: `TemirlanToDo/Views/RootView.swift`
- Create: `TemirlanToDo/Views/TaskListView.swift`
- Create: `TemirlanToDo/Views/TaskRowView.swift`
- Create: `TemirlanToDo/Views/AddTaskComposerView.swift`
- Create: `TemirlanToDo/Views/TaskDetailView.swift`

- [ ] **Step 1: Add app entry point**

Create `TemirlanToDoApp` with a `@StateObject` `TaskStore` and inject it into `RootView`.

- [ ] **Step 2: Add cyberpunk theme**

Create reusable dark/light colors, neon accent helpers, glass panels, and compact button styling using SwiftUI modifiers.

- [ ] **Step 3: Build navigation and task views**

Build a `NavigationView` with a list selector, smart-list screens, search, completed section, bottom composer, row controls, and detail sheet editor.

- [ ] **Step 4: Commit**

Run:

```powershell
git add TemirlanToDo
git commit -m "feat: build SwiftUI task interface"
```

## Task 5: GitHub Build

**Files:**
- Create: `.github/workflows/ios-build.yml`
- Create: `README.md`

- [ ] **Step 1: Add GitHub Actions workflow**

Create a macOS workflow that runs on push and pull request, lists Xcode versions, builds the app for an iPhone simulator with `xcodebuild`, and runs tests.

- [ ] **Step 2: Document signed IPA setup**

Document required Apple Developer secrets and the future archive/export command path.

- [ ] **Step 3: Commit**

Run:

```powershell
git add .github/workflows/ios-build.yml README.md
git commit -m "ci: add GitHub iOS build"
```

## Task 6: Verification

**Files:**
- Modify as needed from previous tasks.

- [ ] **Step 1: Local structural verification**

Run:

```powershell
git status --short
rg --files
```

Expected: project files, Swift files, tests, workflow, and docs are present.

- [ ] **Step 2: CI verification note**

Because this workspace is Windows and does not include Xcode, local `xcodebuild` cannot run here. Final compile verification happens in GitHub Actions on a macOS runner.

- [ ] **Step 3: Commit any final fixes**

Run:

```powershell
git add .
git commit -m "chore: finalize Temirlan To Do project"
```

Only run the final commit if verification changes files.

## Self-Review

- Spec coverage: app name, iOS 15+, SwiftUI, JSON persistence, smart lists, cyberpunk style, GitHub build, tests, and signing documentation are covered.
- Placeholder scan: no TBD/TODO markers are included.
- Type consistency: `TaskItem`, `TaskListKind`, `TaskStorage`, and `TaskStore` names match the design spec.
