# Mobo Sales for Odoo

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-000000?style=for-the-badge&logo=ios&logoColor=white)
![Odoo](https://img.shields.io/badge/Odoo-14--19-875A7B.svg?style=for-the-badge&logo=odoo&logoColor=white)
![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg?style=for-the-badge)

Mobo Sales for Odoo is a powerful mobile application designed to extend Odoo Sales functionality to Android and iOS devices. Built with Flutter, it enables sales teams to manage quotations, customers, and orders directly from their mobile phones, ensuring productivity on the go with real-time Odoo synchronization.

##  Key Features

###  Identity & Access
- **Secure Login**: Authentication with database selection and Odoo session-based auth.
- **2FA Support**: Enhanced security with Two-Factor Authentication.
- **Switch Account**: Seamlessly switch between different user accounts.
- **Biometric Security**: Secure access using Fingerprint or Face ID.

###  Sales & CRM
- **Quotation Workflow**: Create, edit, and manage quotations and sales orders.
- **Digital Signatures**: Capture customer signatures directly on quotations for faster approvals.
- **Customer CRM**: Create and manage detailed customer profiles with interactive maps.
- **Multi-Company Support**: Easily switch between different company environments.

###  Productivity Tools
- **Product Catalog**: Advanced product search with filters, categories, and real-time stock awareness.
- **Barcode Scanning**: Quickly find products or add them to orders using the integrated scanner.
- **Voice Search**: Search for products hands-free using integrated speech-to-text.
- **OCR Integration**: Generate data from text recognition using Google ML Kit.
- **Interactive Maps**: Locate and manage customer addresses with integrated maps.

###  System & Integration
- **Real-Time Sync**: Instant data exchange with the Odoo backend.
- **Domain Filtering**: Precise data retrieval using Odoo domain filters and pagination.
- **User Permissions**: Access control enforced based on Odoo user rights.

##  App Demo

[![Mobo Sales Demo](https://img.youtube.com/vi/CAf-KK6uCB8/0.jpg)](https://www.youtube.com/watch?v=CAf-KK6uCB8)

*Click the image above to watch the Mobo Sales demo on YouTube.*

##  Technology Stack

- **Frontend**: Flutter (Dart)
- **Backend**: Odoo REST APIs / Odoo RPC
- **Authentication**: Odoo Session-based Auth & 2FA
- **State Management**: Provider
- **Architecture**: Clean Architecture / MVC
- **Local Storage**: Shared Preferences & Path Provider

##  Platform Support

- **Android**: 5.0 (API level 21) and above
- **iOS**: 12.0 and above

### Permissions
The app may request:
- **Internet Access**: To sync data with the Odoo server.
- **Storage/Camera**: To cache files/images and for barcode scanning/OCR.
- **Location**: For customer mapping and logistics (if applicable).
- **Microphone**: For voice-based product search.

##  Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Latest Stable)
- Odoo Instance (Tested Versions: 14 - 19 Community & Enterprise)
- Android Studio / VS Code

### Installation

#### 1. Backend Setup (Odoo)
- Install required custom Mobo modules on your Odoo instance.
- Enable API access and configure user access rights.
- Note your Server URL, Database Name, and User Credentials.

#### 2. Mobile App Setup
```bash
# Clone the repository
git clone https://github.com/mobo-suite/mobo_sales.git
cd mobo_sales

# Install dependencies
flutter pub get

# Run the application
flutter run
```

### API Configuration
While the app supports dynamic URL entry on the login screen, you can set default configurations in:
`lib/services/odoo_api_service.dart` (or your specific config file).

### Build Release

**Android**
```bash
flutter build apk --release
```

**iOS**
```bash
flutter build ios --release
```

##  Usage
1. Launch Mobo Sales on your device.
2. Enter your **Odoo Server URL**.
3. Select your **Database** from the list.
4. Login with your **Odoo Credentials**.
5. Start managing your sales pipeline!

##  Troubleshooting

- **Login Failed**: Verify the server URL (ensure `https://`), check the database name, and confirm your user has the necessary Odoo permissions.
- **No Data Loading**: Check your internet connection, verify API endpoints, and ensure the Mobo Odoo modules are correctly installed on the server.
- **Sync Issues**: Check the server logs and ensure your Odoo session hasn't expired.

##  Roadmap
- **Voice-Powered Sales**: Full voice-driven creation of quotations.
- **Offline Synchronization**: Future support for offline data management.
- **Dashboard Analytics**: Enhanced sales performance visualization.
- **Improved Barcode Workflows**: Streamlined multi-product scanning.

##  License
See the [LICENSE](LICENSE) file for the main license and [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for details on included dependencies and their respective licenses.

##  Maintainers
**Team Mobo at Cybrosys Technologies**
- Email: [cybroplay@gmail.com](mailto:cybroplay@gmail.com)
- Website: [cybrosys.com](https://www.cybrosys.com)
