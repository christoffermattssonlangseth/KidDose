# KidDose

A SwiftUI iOS app for tracking ibuprofen and paracetamol doses for multiple children, with real-time CloudKit sync between parents.

## Features

- Track ibuprofen (8h interval) and paracetamol (6h interval) for multiple children
- Real-time CloudKit sync — both parents see dose logs instantly
- Critical Alert notifications that bypass Silent Mode / Do Not Disturb
- Cross-device notifications: "Partner gave Paracetamol to Emma at 3:14 AM"
- CloudKit sharing via `UICloudSharingController` (iMessage, email, or link)
- Live countdown timers to next allowed dose
- Full history with per-child/per-medication filters and stats
- Swipe-to-delete children (cascade deletes all dose history)
- Dark mode support

---

## Manual Xcode Setup (Required)

These steps cannot be automated and must be performed manually in Xcode.

### 1. Bundle Identifier

In **Target → General → Identity**, set:

```
Bundle Identifier: com.yourname.kiddose
```

Replace `yourname` with your own identifier.

### 2. CloudKit Container Identifier

In every file that references `iCloud.com.yourname.kiddose`, replace with your actual container ID:

- `KidDoseApp.swift` — `ModelConfiguration(cloudKitDatabase: .private(...))`
- `CloudKitService.swift` — `CKContainer(identifier: ...)`
- `ChildrenView.swift` — `CKContainer(identifier: ...)`
- `KidDose.entitlements` — `com.apple.developer.icloud-container-identifiers`
- `Info.plist` — `CFBundleIdentifier`

### 3. Capabilities — iCloud + CloudKit

In **Target → Signing & Capabilities**, click **+ Capability** and add:

| Capability | Settings |
|---|---|
| **iCloud** | Check **CloudKit**; select/create container `iCloud.com.yourname.kiddose` |
| **Push Notifications** | Add (required for CloudKit silent pushes) |
| **Background Modes** | Check **Remote notifications** and **Background fetch** |

### 4. Critical Alerts Entitlement

Critical Alerts require explicit approval from Apple.

1. Apply at: <https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/>
2. Once approved, uncomment this key in `KidDose.entitlements`:

   ```xml
   <key>com.apple.developer.usernotifications.critical-alerts</key>
   <true/>
   ```

3. The app falls back gracefully to regular notifications if this entitlement is absent.

### 5. Entitlements File

In **Target → Build Settings → Code Signing Entitlements**, set:

```
KidDose/Resources/KidDose.entitlements
```

### 6. CloudKit Schema Initialization

On first launch in a Simulator or device with a signed-in iCloud account, SwiftData + NSPersistentCloudKitContainer will automatically initialize the CloudKit schema. To do this manually:

1. Run the app once on a device or simulator signed into iCloud.
2. In CloudKit Console (<https://icloud.developer.apple.com>), verify that `CD_Child` and `CD_DoseLog` record types appear under your container's **Development** environment.
3. **Deploy schema to Production** via CloudKit Console when ready for TestFlight/App Store.

### 7. App Store / Production

When submitting:

- Change `aps-environment` in entitlements from `development` to `production`.
- Deploy the CloudKit schema from Development → Production in CloudKit Console.
- Ensure Remote Notifications background mode is listed in your App Store capability list.

---

## Architecture

```
KidDose/
├── Models/
│   ├── Child.swift          # @Model — name, colorHex, doses[]
│   ├── DoseLog.swift        # @Model — medication, timestamp, givenBy
│   └── Medication.swift     # Enum — ibuprofen / paracetamol
├── ViewModels/
│   └── DoseViewModel.swift  # @Observable — dose logic, notifications, stats
├── Services/
│   ├── NotificationManager.swift  # UNUserNotificationCenter wrapper
│   └── CloudKitService.swift      # CKQuerySubscription + push handling
├── Views/
│   ├── ContentView.swift    # TabView root
│   ├── Home/
│   │   ├── HomeView.swift         # Child selector + medication cards
│   │   └── MedicationCard.swift   # Card + live countdown
│   ├── History/
│   │   └── HistoryView.swift      # Filtered dose log + stats
│   ├── Children/
│   │   ├── ChildrenView.swift     # List + sharing button
│   │   ├── AddChildSheet.swift    # Name + color picker
│   │   └── CloudSharingController.swift  # UICloudSharingController wrapper
│   └── Shared/
│       ├── iCloudBanner.swift     # "Not signed in" banner
│       └── ColorExtensions.swift  # hex ↔ Color helpers + preset palette
├── AppDelegate.swift        # Remote push notification handling
├── KidDoseApp.swift         # @main, ModelContainer, CloudKit config
└── Resources/
    ├── Info.plist
    └── KidDose.entitlements
```

---

## Notification Flow

```
Dose logged on Device A
  └─▶ SwiftData saves DoseLog
  └─▶ CloudKit syncs record
  └─▶ CloudKit fires CKQuerySubscription → silent push to Device B
        └─▶ AppDelegate.didReceiveRemoteNotification
        └─▶ CloudKitService.handleRemoteNotification
        └─▶ Local notification: "Alex gave Ibuprofen to Emma at 2:30 AM"

Dose interval elapses (locally, any device)
  └─▶ UNTimeIntervalNotificationTrigger fires Critical Alert
        "Ibuprofen ready for Emma"
```

---

## Requirements

- iOS 17+
- Xcode 15+
- Active Apple Developer account (required for CloudKit and Critical Alerts)
- iCloud account signed in on device

---

## Replacing the Placeholder Bundle ID

Search the project for `com.yourname.kiddose` and replace all occurrences with your actual reverse-DNS identifier before building.
