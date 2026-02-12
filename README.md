# 🔐 Desktop Encryption Client – UI Demo (v1.2)

A Flutter Windows desktop application demonstrating the **UI/UX redesign and workflow improvements** delivered in version **v1.2** of an enterprise encryption system.

This repository focuses **purely on the frontend, interaction design, and user experience**.

> ⚠️ Important  
> Backend APIs, encryption engines, authentication, hardware integrations, and sensitive company components are **removed or replaced with mock implementations**.

---

---

# ✨ My Contribution

I worked primarily on the **UI transformation from Cryptoseal v1.1 → v1.2**.

Key areas of responsibility:

- Workspace features added 
- File lifecycle automation  
- Explorer interaction improvements  
- Utility encryption flow  
- Toast / overlay feedback system  
- Progress indicators  
- Desktop transition animations  
- Removal of backend dependency for demo usage  

---

---

# 🧰 Tech Stack

- Flutter Desktop (Windows)
- Dart
- Glass / blur modern UI
- Stateful architecture
- Mocked service layer
- Animated transitions

---

---

# 🚀 Getting Started

## 1️⃣ Clone the Repository

```bash
git clone https://github.com/yourusername/Desktop_Encryption_Client_UI_Demo.git
```

```bash
cd Desktop_Encryption_Client_UI_Demo
```

## 🖥 Requirements

Make sure you have:

- Flutter SDK (latest stable)
- Windows 10 or later
- Visual Studio with **Desktop development with C++**

Verify with:

```bash
flutter doctor
```

Ensure Windows desktop is enabled.

---

---

## ▶ Run the Application (Debug Mode)

```bash
flutter clean
flutter pub get
flutter run -d windows
```

## 📦 Build Release

```bash
flutter build windows
```

# 🔐 Application Overview

The system provides **two main operating modes**:

```
Workspace Tab  → Secure daily operations
Utility Tab    → Quick standalone encryption/decryption
```

Each serves a different user purpose.

---

# 🗂 Workspace Tab (Controlled Secure Environment)

Workspace mode is designed for **safe editing of protected documents**.

### Restrictions inside Workspace:

- Encryption type = **AES256**
- Key group = **PERSONAL**
- Users cannot modify algorithm or key.

---

## 📥 Importing a File

When a user imports a file:

```
report.docx
↓
report.docx.aes256
```

The file becomes encrypted automatically.

---

## 🖱 Opening / Working With Files

When the user double-clicks an encrypted file:

1. File is decrypted.
2. It opens using the system default application.
3. User edits normally.

---

## 🔁 Automatic Re-Encryption (Core Feature)

When the user saves or closes the file:

✔ Background system detects closure  
✔ File is unlocked  
✔ File is re-encrypted  
✔ Previous encrypted version is replaced  

This cycle can repeat **unlimited times**.

---

## 📤 Exporting

When exporting:

1. Latest version is decrypted.
2. Saved to user chosen location.
3. Encrypted copy is removed from workspace.

This ensures the workspace contains only protected materials.

---

# 🧪 Utility Tab (On-Demand Encryption)

Utility mode allows encryption/decryption **outside** the workspace.

Here, the user **can choose**:

### Algorithms
- AES256  
- Threefish  
- ChaCha20  

### Key Groups
Provided by backend in production, mocked in demo.

---

## 🧠 How Utility Works

User selects file/folder → presses Encrypt/Decrypt → console runs.

In real system:
- External engines are executed.

In this demo:
- Execution is simulated.
- Console messages are mocked.
- No real encryption occurs.

---

# 🧩 Demo vs Production Comparison

| Component              | Demo         | Real System     |
|------------------------|--------------|-----------------|
| API communication      | ❌ Removed   | ✅ Active      |
| Login/session          | ❌ Removed   | ✅ Secure      |
| Hardware dongle        | ❌ Removed   | ✅ Required    |
| Encryption executables | ❌ Simulated | ✅ Real        |
| Audit logging          | ❌ Mocked    | ✅ Server side |

---

# 🎯 What This Project Demonstrates

This repository highlights my ability to:

- Design secure UX flows  
- Translate enterprise requirements into usable interfaces  
- Improve legacy UI systems  
- Separate UI from infrastructure  
- Handle complex file lifecycle logic  
- Work on desktop-grade applications  

---

# 🧱 Project Structure (Simplified)

```
lib/
 ├── pages/
 │   ├── splash/
 │   ├── initial/
 │   └── subpages/
 │        ├── workspace
 │        └── utility
 ├── utils/
assets/
```

# 🧑‍💻 Author

Frontend & UX modernization project  
Desktop security application (enterprise internship work)

---

# 📌 Notes

This is a **portfolio-safe build**.

Sensitive business logic, proprietary engines, and internal services are intentionally excluded.

---

