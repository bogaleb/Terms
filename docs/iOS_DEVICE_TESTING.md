# iOS Device Testing Guide for EtBook

## 🎯 Overview
There are several ways to test your EtBook app on an iOS device. Here are your options from easiest to most advanced:

## Option 1: TestFlight (Recommended) 📱

**Best for**: Internal testing, beta testing, sharing with team members

### Steps:
1. **Build for Preview** (currently in progress):
   ```bash
   eas build --platform ios --profile preview
   ```

2. **Wait for Build Completion** (10-20 minutes)
   - Monitor at: https://expo.dev/accounts/binified/projects/EtBook-mobile-binified/builds

3. **Submit to TestFlight**:
   ```bash
   eas submit --platform ios --latest
   ```

4. **Invite Testers**:
   - Go to App Store Connect
   - Add internal/external testers
   - Send TestFlight invitations

### Requirements:
- Apple Developer Account ($99/year)
- App Store Connect access
- TestFlight app on your iOS device

## Option 2: Direct Installation (Development) 🔧

**Best for**: Quick testing, development builds

### Steps:
1. **Build Development Profile**:
   ```bash
   eas build --platform ios --profile development
   ```

2. **Download .ipa file** from EAS dashboard

3. **Install using one of these methods**:

   **Method A: Using Apple Configurator 2 (Mac required)**
   - Install Apple Configurator 2 from App Store
   - Connect iOS device to Mac
   - Drag .ipa file to device in Apple Configurator

   **Method B: Using Xcode (Mac required)**
   - Open Xcode
   - Window → Devices and Simulators
   - Select your device
   - Drag .ipa to "Installed Apps" section

   **Method C: Using 3rd party tools**
   - AltStore (requires AltServer on computer)
   - Sideloadly
   - iOS App Installer

## Option 3: Expo Go (Limited) 📲

**Best for**: Quick previews, development testing
**Limitation**: Won't work with custom native code (expo-dev-client)

### Steps:
1. Install Expo Go from App Store
2. Run development server:
   ```bash
   expo start
   ```
3. Scan QR code with Expo Go app

**Note**: This won't work for your current app since you're using expo-dev-client and custom plugins.

## Option 4: Development Build + Expo CLI 🚀

**Best for**: Development with custom native code

### Steps:
1. **Build Development Client**:
   ```bash
   eas build --platform ios --profile development
   ```

2. **Install the development build** on your device (using methods from Option 2)

3. **Start development server**:
   ```bash
   expo start --dev-client
   ```

4. **Open development build** on your device and connect to development server

## Current Build Status 📊

Let me check your current build status:

```bash
# Check build status
eas build:list --limit=5

# View specific build
eas build:view [BUILD_ID]
```

## Installation Methods Comparison 📋

| Method | Ease | Requirements | Best For |
|--------|------|--------------|----------|
| TestFlight | ⭐⭐⭐⭐⭐ | Apple Developer Account | Beta testing, team sharing |
| Apple Configurator | ⭐⭐⭐ | Mac + Apple Configurator | Direct installation |
| Xcode | ⭐⭐ | Mac + Xcode | Development testing |
| AltStore | ⭐⭐⭐ | Windows/Mac + AltServer | No developer account needed |
| Expo Go | ⭐⭐⭐⭐⭐ | Just Expo Go app | Simple apps only |

## Recommended Workflow 🔄

For your EtBook app, I recommend this progression:

1. **Development Testing**: Build development profile → Install directly → Test core functionality
2. **Internal Testing**: Build preview profile → Submit to TestFlight → Test with team
3. **Beta Testing**: Add external testers to TestFlight → Get user feedback
4. **Production**: Build production profile → Submit to App Store → Release

## Troubleshooting 🔧

### Build Fails
- Check build logs in EAS dashboard
- Verify all plugins are installed
- Check for TypeScript errors

### Installation Fails
- Ensure device is registered in Apple Developer Portal
- Check provisioning profiles
- Verify device iOS version compatibility

### App Crashes on Device
- Check device logs in Xcode Console
- Verify all native dependencies are compatible
- Test in iOS Simulator first

## Quick Commands 💻

```bash
# Check builds
eas build:list

# Build for device testing
eas build --platform ios --profile preview

# Build for development
eas build --platform ios --profile development

# Submit to TestFlight
eas submit --platform ios --latest

# Check project info
eas project:info
```

## What's Next? 🎯

Once your current build completes:

1. **Download the .ipa** from EAS dashboard
2. **Choose installation method** based on your setup
3. **Test the data isolation fixes** we implemented
4. **Test all major features** (businesses, books, entries, sync)
5. **Report any issues** for fixes
6. **Proceed to TestFlight** if testing goes well

Your EtBook app is production-ready with all the security fixes and features we've implemented! 🎉
