# Temirlan To Do

Temirlan To Do is a native iOS 15+ SwiftUI task app inspired by Microsoft To Do. It uses local JSON file storage and a modern cyberpunk visual style with cyan, magenta, and amber accents.

## Features

- Smart lists: My Day, Important, Planned, and Tasks.
- Create, edit, complete, delete, and search tasks.
- Mark tasks as important.
- Add due dates and notes.
- Local persistence in Application Support as JSON.
- SwiftUI interface with dark cyberpunk styling and system iOS controls.
- Personal AI Assistant powered by the OpenAI API.

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

## AI Assistant

The app includes a personal AI Assistant. It calls the OpenAI API directly from the iPhone and stores your API key in iOS Keychain.

Get an API key here:

[https://platform.openai.com/api-keys](https://platform.openai.com/api-keys)

Important notes:

- Do not commit your API key to GitHub.
- Do not paste the key into source files.
- Enter the key only inside the app's AI Assistant setup screen.
- ChatGPT Plus and OpenAI API billing are separate. The API key usually requires billing or credits on OpenAI Platform.

Assistant features:

- Break a task into smaller steps.
- Plan the day from current tasks.
- Create tasks from natural language.
- Improve task wording.
- Preview suggested changes before applying them.

### OpenAI 429 Error

If the app shows `OpenAI returned 429`, check these OpenAI Platform pages:

- Billing: [https://platform.openai.com/settings/organization/billing](https://platform.openai.com/settings/organization/billing)
- Usage: [https://platform.openai.com/usage](https://platform.openai.com/usage)
- Limits: [https://platform.openai.com/settings/organization/limits](https://platform.openai.com/settings/organization/limits)

Common causes:

- No API credits or billing method on OpenAI Platform.
- Monthly usage limit reached.
- Requests are being sent too quickly.
- The selected model is limited for the current usage tier.

ChatGPT subscription does not automatically pay for OpenAI API usage.

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
