# Google Cloud Setup Guide: Calendar & Gmail APIs

This guide walks you through creating a Google Cloud Project from scratch, enabling Google Sign-In and the required APIs, generating the correct OAuth credentials, and configuring both Android and iOS to run this Flutter application locally.

## Step 1: Create a Google Cloud Project

1. Go to the [Google Cloud Console](https://www.google.com/search?q=https://console.cloud.google.com).
2. Click the project dropdown in the top-left corner (next to the Google Cloud logo) and click **New Project**.
3. Name your project (e.g., `Vision Assistant Edge AI`) and click **Create**.
4. Once created, ensure your new project is selected in the top dropdown menu.

## Step 2: Enable the Required APIs

To allow the AI to access your calendar and email, you must activate the corresponding APIs.

1. In the left sidebar, navigate to **APIs & Services** > **Library**.
2. Search for **Google Calendar API**, click it, and select **Enable**.
3. Go back to the Library, search for **Gmail API**, click it, and select **Enable**.

## Step 3: Configure the OAuth Consent Screen

Google requires a consent screen to inform users what data the app is requesting.

1. Navigate to **APIs & Services** > **OAuth consent screen**.
2. Select **External** as the User Type and click **Create**.
3. Fill out the required fields:
* **App name:** (e.g., `Vision Assistant Local`)
* **User support email:** Select your email.
* **Developer contact information:** Enter your email.
4. Click **Save and Continue**.


## Step 4: Link to Firebase & Enable Google Sign-In Provider (Optional / If Using Firebase Configs)

If your app uses `google-services.json` or `GoogleService-Info.plist`, connect this Google Cloud project to Firebase instead of creating a second project:

1. Open the [Firebase Console](https://console.firebase.google.com/).
2. Click **Create a new Firebase Project**.
3. Click the **Add Firebase to Google Cloud project** at bottom left, then click the dropdown and **select your existing Google Cloud project** from the list.
4. Accept the terms and click **Continue** (you can disable Google Analytics for local dev).
5. In the Firebase project sidebar, go to **Security** > **Authentication**.
6. Click **Get Started**, then select the **Sign-in method** tab.
7. Click **Google** under Additional providers:
* Toggle **Enable**.
* Choose a **Project support email**.
* Ensure the **Web SDK configuration** automatically reflects your Web Client ID.
* Click **Save**.


## Step 5: Generate Your Local SHA-1 Fingerprint (For Android)

To authorize your specific computer to build the Android app, you need the SHA-1 fingerprint of your local debug keystore.

Open your terminal or command prompt and run the following command:

**For macOS / Linux:**

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android

```

**For Windows:**

```cmd
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android

```

*Note: If the `debug.keystore` does not exist yet, build the Flutter app for Android once (`flutter build apk --debug`), and the system will generate it automatically.*

Copy the 20-byte hex string labeled **SHA1** from the output.

## Step 6: Create the Android OAuth Client

This step registers your Android app with Google Cloud.

1. Navigate to **APIs & Services** > **Credentials**.
2. Click **+ Create Credentials** > **OAuth client ID**.
3. Select **Android** as the Application type.
4. Fill in the details:
* **Name:** `Android Client`
* **Package name:** Find this in your Flutter project inside `android/app/build.gradle` (e.g., `com.gdgapu.visual_assistant`).
* **SHA-1 certificate fingerprint:** Paste the SHA-1 string you copied in Step 4.


5. Click **Create**.


## Step 7: Create the iOS OAuth Client (For iOS)

This step registers your iOS app with Google Cloud.

1. Still on the **Credentials** page, click **+ Create Credentials** > **OAuth client ID**.
2. Select **iOS** as the Application type.
3. Fill in the details:
* **Name:** `iOS Client`
* **Bundle ID:** Find this in Xcode or in your Flutter project under `ios/Runner.xcodeproj/project.pbxproj` (typically matches your Android package without underscores, e.g., `com.gdgapu.visualassistant`).


4. Click **Create**.
5. A dialog will appear. Copy the **iOS URL scheme** (also known as the `REVERSED_CLIENT_ID`, which looks like `com.googleusercontent.apps.123456789-abcdefg`). You will need this in Step 8.

## Step 8: Create the Web OAuth Client (Required for Server Auth & Scopes)

Even though this is a mobile app, the `google_sign_in` package requires a **Web application** Client ID to request a server auth code for the `googleapis` backend tools.

1. Still on the **Credentials** page, click **+ Create Credentials** > **OAuth client ID**.
2. Select **Web application** as the Application type.
3. Name it `Web Client`.
4. You do **not** need to add any Authorized JavaScript origins or Redirect URIs. Leave them blank.
5. Click **Create**.
6. Copy the **Client ID** (it ends in `.apps.googleusercontent.com`). This is your `GOOGLE_SERVER_CLIENT_ID`.

## Step 9: Configure iOS App (`Info.plist`)

To allow Google Sign-In to redirect back to your app on iOS, you must add the URL scheme you generated in Step 6 to your iOS project.

1. Open `<project_root>/ios/Runner/Info.plist` in your code editor.
2. Add the following snippet inside the main `<dict>` tag, replacing `YOUR_IOS_URL_SCHEME_HERE` with the iOS URL scheme you copied in Step 6:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <!-- Copied from Google Cloud Console -> iOS Client -> iOS URL scheme -->
      <string>YOUR_IOS_URL_SCHEME_HERE</string>
    </array>
  </dict>
</array>

```

### Config Files (If using Firebase services)

* **Android:** In Firebase Console > Settings / Project Settings, add an Android app with package `com.gdgapu.visual_assistant` and your SHA-1. Download `google-services.json` and move it to `android/app/google-services.json`.
* **iOS:** Add an iOS app with your Bundle ID. Download `GoogleService-Info.plist` and move it into `ios/Runner/` via Xcode.

## Step 10: Configure Your Environment File

1. In the root of your Flutter project, copy the example environment file:

```bash
cp .env.example .env

```

2. Open the `.env` file in your text editor.
3. Paste the **Web Client ID** you copied in Step 7 into the `GOOGLE_SERVER_CLIENT_ID` variable.
4. Add your Hugging Face read access token.

Your final `.env` file should look like this:

```env
# Read access token in Hugging Face 
# https://huggingface.co/settings/tokens/new?tokenType=read
HUGGINGFACE_TOKEN=hf_YourActualTokenHere

# OAuth Client ID (Web Application type) for Google Services
GOOGLE_SERVER_CLIENT_ID=123456789-abcdefg.apps.googleusercontent.com

```

## Run the App

You can now run the app on your device. When you tap "Sign in with Google", it will authenticate securely against your personal Google Cloud Project.

```bash
flutter run

```

*(Alternatively, if you prefer not to use a `.env` file, you can pass the client ID directly at build time: `flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=your-web-client-id.apps.googleusercontent.com`)*