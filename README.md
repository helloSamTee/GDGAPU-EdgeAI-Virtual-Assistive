# gdg_edge_ai

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

## Google Sign-In

Create an OAuth 2.0 **Web application** client in the same Google Cloud
project as the Android client, then start the app with its client ID:

```bash
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
```

The Android OAuth client must use package name `com.gdgapu.visual_assistant`
and the SHA-1 certificate of the key used to install the app. The downloaded
Firebase configuration file should be named `google-services.json` and placed
in `android/app/`.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on using Flutter, and a full API reference.
