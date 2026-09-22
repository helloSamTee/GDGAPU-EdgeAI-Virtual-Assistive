# Google Cloud Setup Guide: Calendar & Gmail APIs

This guide walks you through creating a Google Cloud Project from scratch, enabling the required APIs, and generating the correct OAuth credentials to run this Flutter application locally.

## Step 1: Create a Google Cloud Project

1. Go to the [Google Cloud Console](https://www.google.com/search?q=https://console.cloud.google.com/&utm_source=gemini).
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
5. On the **Scopes** screen, click **Add or Remove Scopes** and manually add these two scopes (if they don't appear, you can paste the URLs directly):
* `[https://www.googleapis.com/auth/calendar.events](https://www.googleapis.com/auth/calendar.events)`
* `[https://www.googleapis.com/auth/gmail.readonly](https://www.googleapis.com/auth/gmail.readonly)`


6. Click **Save and Continue**.
7. On the **Test users** screen, click **Add Users** and add the exact Google email address you plan to use when signing into the app on your phone.
8. Click **Save and Continue**, then review and return to the dashboard.

## Step 4: Generate Your Local SHA-1 Fingerprint

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

## Step 5: Create the Android OAuth Client

This step registers your Android app with Google Cloud.

1. Navigate to **APIs & Services** > **Credentials**.
2. Click **+ Create Credentials** > **OAuth client ID**.
3. Select **Android** as the Application type.
4. Fill in the details:
* **Name:** `Android Client`
* **Package name:** Find this in your Flutter project inside `android/app/build.gradle` (`com.gdgapu.visual_assistant`).
* **SHA-1 certificate fingerprint:** Paste the SHA-1 string you copied in Step 4.


5. Click **Create**.

## Step 6: Create the Web OAuth Client (Crucial Step)

Even though this is an Android app, the `google_sign_in` package requires a **Web application** Client ID to request a server auth code for the `googleapis` backend tools.

1. Still on the **Credentials** page, click **+ Create Credentials** > **OAuth client ID**.
2. Select **Web application** as the Application type.
3. Name it `Web Client`.
4. You do **not** need to add any Authorized JavaScript origins or Redirect URIs. Leave them blank.
5. Click **Create**.
6. A dialog will appear with your Client ID. Copy the **Client ID** (it ends in `.apps.googleusercontent.com`). This is your `GOOGLE_SERVER_CLIENT_ID`.

## Step 7: Configure Your Environment File

1. In the root of your Flutter project, copy the example environment file:
```bash
cp .env.example .env

```


2. Open the `.env` file in your text editor.
3. Paste the **Web Client ID** you copied in Step 6 into the `GOOGLE_SERVER_CLIENT_ID` variable.
4. Add your Hugging Face read access token.

Your final `.env` file should look like this:

```env
# Read access token in Hugging Face 
# https://huggingface.co/settings/tokens/new?tokenType=read
HUGGINGFACE_TOKEN=hf_YourActualTokenHere

# OAuth Client ID (Web Application type) for Google Services
GOOGLE_SERVER_CLIENT_ID=123456789-abcdefg.apps.googleusercontent.com

```

You can now run `flutter run` on your device. When you tap "Sign in with Google", it will authenticate securely against your personal Google Cloud Project.
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
