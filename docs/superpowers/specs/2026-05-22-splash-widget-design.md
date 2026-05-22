# Splash And Today Widget Design

## Summary

Temirlan To Do will add a short animated splash transition inside the app and a Today widget that shows the number of today's tasks plus a short list of task titles.

The splash is implemented in SwiftUI after launch, not as an animated app icon. The widget is implemented as a WidgetKit extension and reads a compact task snapshot from shared user defaults.

## Goals

- Add a 1-second cyberpunk launch transition after app startup.
- Keep the existing iOS LaunchScreen static and fast.
- Add a WidgetKit Today widget for iOS 15+.
- Show today's active task count and up to three short task titles.
- Keep widget code small and independent from app UI.

## Non-Goals

- No animated home-screen app icon, because iOS does not support that.
- No interactive widget controls in version 1.
- No widget editing/configuration in version 1.

## Splash UX

On launch, the app briefly shows a full-screen dark cyberpunk background. The app icon mark scales in, a cyan ring pulses once, and the title appears. The splash then fades into the main task UI.

The animation should finish automatically and not block app use for more than roughly one second.

## Widget UX

The widget is named "Today Tasks". It shows:

- Header: "Today"
- Count: active tasks due today or marked My Day
- Up to three task titles
- Empty state: "Clear signal"

The widget uses a dark background with cyan/magenta accents to match the app.

## Data Flow

The app saves a compact `TodayWidgetSnapshot` whenever tasks are saved. The widget reads that snapshot and renders it. The snapshot contains only count, titles, and last update date.

If App Groups are unavailable in a sideloaded build, the widget may show an empty state until signing is configured with the same app group for app and extension.
