# Temirlan To Do

Temirlan To Do is a native iOS 15+ SwiftUI task app inspired by Microsoft To Do. It uses local JSON file storage and a modern cyberpunk visual style with cyan, magenta, and amber accents.

## Features

- Smart lists: My Day, Important, Planned, and Tasks.
- Create, edit, complete, delete, and search tasks.
- Mark tasks as important.
- Add due dates and notes.
- Local persistence in Application Support as JSON.
- SwiftUI interface with dark cyberpunk styling and system iOS controls.

## Project

- App target: `TemirlanToDo`
- Test target: `TemirlanToDoTests`
- Bundle ID: `com.temirlan.todo`
- Minimum iOS: `15.0`

## GitHub Build

The workflow in `.github/workflows/ios-build.yml` runs on a macOS runner:

```bash
xcodebuild \
  -project TemirlanToDo.xcodeproj \
  -scheme TemirlanToDo \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

It also runs the XCTest target.

## Sideloadly IPA Without Apple Developer

The workflow also creates an unsigned device IPA for Sideloadly:

1. Push the project to GitHub.
2. Open `Actions` -> `iOS Build`.
3. Open the latest successful run.
4. Download the `TemirlanToDo-unsigned-ipa` artifact.
5. Extract the downloaded artifact zip. Inside it is `TemirlanToDo-unsigned.ipa`.
6. Open Sideloadly on Windows or macOS.
7. Connect the iPhone by USB.
8. Drag `TemirlanToDo-unsigned.ipa` into Sideloadly.
9. Enter your Apple ID and start installation.
10. On the iPhone, trust the developer profile in Settings if iOS asks for it.

With a free Apple ID, the app usually needs to be reinstalled after 7 days. If the iPhone is on iOS 16 or newer and asks for Developer Mode, enable it in Settings and reboot the device.

## Signed IPA

Unsigned simulator builds work immediately in GitHub Actions. To export a signed IPA, add Apple Developer signing secrets:

- `APPLE_CERTIFICATE_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_PROVISIONING_PROFILE_BASE64`
- `APPLE_TEAM_ID`
- `IOS_BUNDLE_ID`
- `IOS_PROVISIONING_PROFILE_NAME`
- `KEYCHAIN_PASSWORD`

Then run the `iOS Build` workflow manually, enable `build_signed_ipa`, and choose the export method. The workflow imports the certificate into a temporary keychain, installs the provisioning profile, archives with `xcodebuild archive`, exports with `xcodebuild -exportArchive`, and uploads the `.ipa` artifact.
