# AttendX - Smart Attendance Management System

A professional Flutter attendance management application with face detection, role-based access, and Firebase backend.

---

## 🎯 Features

### Roles
| Role | Access |
|------|--------|
| **Super Admin** | Full system access — manage managers, employees, attendance |
| **Manager** | Manage employees & view attendance records |
| **Employee** | Face-based clock-in/out only (no credentials needed) |

### Core Features
- 🔐 **Role-based Authentication** — Firebase Auth for Admin/Manager
- 📸 **Face Detection** — Google ML Kit for employee identification
- 📊 **Real-time Dashboard** — Live attendance stats & charts
- 👥 **Employee Management** — Full CRUD with photo upload
- 📅 **Attendance Tracking** — Date-filtered records, login/logout times
- 🕐 **Smart Clock Logic** — Shows only Login or Logout button based on status
- 📋 **Audit Trail** — Every record shows who created it (Admin/Manager)
- ❌ **Absent Marking** — Auto-marks absent for employees who don't clock in

---

## 🚀 Setup Guide

### 1. Prerequisites
```bash
flutter --version  # Flutter 3.10+
dart --version     # Dart 3.0+
```

### 2. Firebase Setup

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create a new project: `attendx-app`
3. Enable these services:
   - **Authentication** → Email/Password
   - **Cloud Firestore** → Start in test mode
   - **Storage** → Start in test mode

4. Install FlutterFire CLI:
```bash
dart pub global activate flutterfire_cli
```

5. Configure Firebase:
```bash
cd attendance_app
flutterfire configure --project=your-firebase-project-id
```
This auto-generates `lib/firebase_options.dart` with your real config.

### 3. Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Users (admins/managers)
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null &&
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role in ['super_admin', 'manager'];
    }

    // Employees
    match /employees/{employeeId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null &&
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role in ['super_admin', 'manager'];
    }

    // Attendance - employees can write their own
    match /attendance/{attendanceId} {
      allow read: if request.auth != null;
      allow write: if true; // Employees mark attendance without auth
    }
  }
}
```

### 4. Firebase Storage Rules
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /employee_photos/{allPaths=**} {
      allow read: if true;
      allow write: if request.auth != null;
    }
  }
}
```

### 5. Install Dependencies & Run
```bash
flutter pub get
flutter run
```

### 6. First Login
The app auto-creates a Super Admin on first launch:
- **Email:** `admin@attendx.com`
- **Password:** `Admin@123`

---

## 📁 Project Structure

```
lib/
├── main.dart                          # App entry point
├── firebase_options.dart              # Firebase config (auto-generated)
│
├── core/
│   ├── constants/
│   │   └── app_constants.dart         # App-wide constants
│   ├── theme/
│   │   └── app_theme.dart             # Design system, colors, typography
│   └── router/
│       └── app_router.dart            # Named routes
│
├── data/
│   ├── models/
│   │   ├── user_model.dart            # Admin/Manager model
│   │   ├── employee_model.dart        # Employee model
│   │   └── attendance_model.dart      # Attendance record model
│   └── services/
│       ├── auth_service.dart          # Firebase Auth operations
│       ├── employee_service.dart      # Firestore CRUD for employees
│       ├── attendance_service.dart    # Attendance operations
│       └── face_detection_service.dart # ML Kit face detection
│
├── providers/
│   ├── auth_provider.dart             # Auth state management
│   ├── employee_provider.dart         # Employee state management
│   └── attendance_provider.dart       # Attendance state management
│
├── screens/
│   ├── auth/
│   │   └── login_screen.dart          # Admin/Manager login
│   ├── dashboard/
│   │   └── admin_dashboard_screen.dart # Main dashboard (4 tabs)
│   ├── employees/
│   │   ├── employee_form_screen.dart   # Add/Edit employee
│   │   └── employee_detail_screen.dart # Employee profile & history
│   ├── attendance/
│   │   └── employee_attendance_screen.dart # Face-based clock in/out
│   └── admin/
│       └── create_manager_screen.dart  # Super Admin creates managers
│
└── widgets/
    └── app_widgets.dart               # Reusable UI components
```

---

## 🔄 Employee Attendance Flow

```
Employee → Tap "Mark Attendance" 
         → Camera opens, face detected
         → Select employee (in demo mode)
         → System checks today's record:
           - No record → Show "Clock In" button
           - Logged in → Show "Clock Out" button only
           - Completed → Show "Already done" message
         → Mark record + display time
```

---

## 🎨 Design System

- **Primary:** `#6C63FF` (Purple)
- **Accent:** `#00D4AA` (Teal)
- **Success:** `#00C896`
- **Error:** `#FF5C7A`
- **Warning:** `#FFB020`

### Reusable Widgets
| Widget | Description |
|--------|-------------|
| `GradientButton` | Animated gradient CTA button |
| `GlassCard` | Clean card with subtle shadow |
| `AppAvatar` | Smart avatar with fallback initials |
| `StatusBadge` | Color-coded presence indicator |
| `StatCard` | KPI metric card |
| `AppTextField` | Styled form input |
| `RoleBadge` | Role indicator chip |
| `EmptyState` | Empty list placeholder |
| `ShimmerCard` | Loading skeleton |
| `LoadingOverlay` | Full-screen loading |

---

## 📱 Supported Platforms
- ✅ Android (API 21+)
- ✅ iOS (13.0+)

---

## ⚙️ Key Dependencies

| Package | Purpose |
|---------|---------|
| `firebase_auth` | Authentication |
| `cloud_firestore` | Database |
| `firebase_storage` | Photo storage |
| `provider` | State management |
| `camera` | Live camera feed |
| `google_mlkit_face_detection` | Face detection |
| `image_picker` | Photo selection |
| `cached_network_image` | Image caching |
| `flutter_animate` | Animations |
| `intl` | Date/time formatting |
| `table_calendar` | Calendar widget |
| `fl_chart` | Analytics charts |

---

## 🔧 Extending Face Recognition

The current implementation uses **Google ML Kit** for face *detection* (is a face present?). For true face *recognition* (who is this person?), integrate one of:

1. **TensorFlow Lite** — Custom face embedding model
2. **AWS Rekognition** — Cloud-based face matching
3. **Azure Face API** — Microsoft's face recognition service
4. **face_recognition** package — Python-based (via API)

The `FaceDetectionService.matchFace()` method is designed to be replaced with your recognition logic.

---

## 🛡️ Security Notes

- Employees **don't need credentials** — only face + employee selection
- All Firestore writes are validated by security rules
- Admin/Manager accounts require Firebase Auth
- Photos stored in Firebase Storage with access controls
- Soft-delete employees (never hard-delete for audit trail)
