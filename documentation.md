# InSight Application Documentation

## Main Function Overview (`lib/main.dart`)

The `main` function serves as the entry point for the Flutter application. Its primary responsibilities are structured to ensure the app is fully initialized and can operate seamlessly online or offline:

1. **Framework Initialization:** Calls `WidgetsFlutterBinding.ensureInitialized()` to ensure Flutter's rendering engine is ready before executing background tasks.
2. **Firebase Setup:** Attempts to connect to Firebase services using the platform-specific credentials stored in `firebase_options.dart`.
3. **Repository Instantiation:** Creates an instance of `SyncedTrackingRepository`, which acts as the data management layer responsible for synchronizing local and cloud data.
4. **Local Data Pre-loading:** Awaits the `loadPersistedPeople()` method from the repository to load active tracking sessions from the local SQLite database. This ensures the app populates data instantly upon launch, regardless of internet connectivity.
5. **State Management & App Launch:** Uses `runApp()` to start the application. It wraps the core `MultiCamTrackingApp` widget inside a `ChangeNotifierProvider`, injecting the `TrackingProvider`. This setup allows any screen within the application to access real-time tracking data and simulation logic efficiently.

## Dart Files and Their Purposes

### `lib/main.dart`
This file contains the core architecture of the app. Aside from the `main` function, it includes the root `MultiCamTrackingApp` widget (defining themes and navigation), core data models (`CameraLog` and `TrackedPerson`), the state management logic (`TrackingProvider`), and the `MainNavigationScreen` that manages the bottom navigation bar and tabs.

### `lib/login_screen.dart`
Provides the staff login interface. It captures the user's email and password, utilizing Firebase Authentication to verify credentials. It also includes error handling for incorrect logins and a password reset feature.

### `lib/register_screen.dart`
Provides the interface for creating new staff accounts. It securely passes user input to Firebase Authentication to create an account, sets the user's display name, and transitions them into the main dashboard upon success.

### `lib/reports_screen.dart`
A comprehensive analytics dashboard. It queries the local SQLite database to display historical and daily statistics, including total foot traffic, average dwell times, hourly entry line charts, and zone occupancy rankings.

### `lib/db/database_helper.dart`
The core local storage manager. It configures and initializes the SQLite database (with cross-platform support via sqflite_ffi). It contains all SQL statements for table creation, data insertion, updates, transaction management, and complex read queries used by the analytics dashboard.

### `lib/repository/tracking_repository.dart`
Defines the data synchronization layer. It implements an offline-first architecture via the `SyncedTrackingRepository`. This class writes data to SQLite instantly for a responsive UI, while simultaneously syncing the data with Cloud Firestore. It also handles retrieving data updates from Firestore and pushing unsynced local data when the device reconnects to the internet.

### `lib/firebase_options.dart`
An auto-generated file created by the FlutterFire CLI. It contains the specific API keys, app IDs, and project configurations required to securely connect the app to the Firebase backend for supported platforms (e.g., Android, Web).

### `test/widget_test.dart`
Contains automated widget tests used to verify that the application renders its core components (such as the login screen) correctly without crashing.
