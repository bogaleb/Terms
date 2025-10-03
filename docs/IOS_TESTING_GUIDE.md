# EtBook Mobile - iOS Testing Guide

This guide will help you build and test the EtBook mobile app on iOS devices and simulators using EAS Build.

## Prerequisites

### Required Software
- **Node.js** (18.x or higher)
- **npm** or **yarn**
- **EAS CLI**: `npm install -g @expo/eas-cli`
- **Expo CLI**: `npm install -g @expo/cli`

### For iOS Development
- **macOS** (for local simulator testing)
- **Xcode** (latest version)
- **iOS Simulator** (included with Xcode)
- **Apple Developer Account** (for device testing and App Store)

### For Device Testing
- **Apple Developer Program** membership ($99/year)
- **Provisioning Profiles** and **Certificates**
- **TestFlight** access (for internal testing)

## Quick Start

### 1. Environment Setup

```bash
# Clone and setup the project
cd c:\Projects\EtBook-mobile

# Install dependencies
npm install

# Copy environment variables
cp .env.example .env

# Edit .env file with your values
# - EXPO_PROJECT_ID: Your EAS project ID
# - EXPO_PUBLIC_SUPABASE_URL: Your Supabase URL
# - EXPO_PUBLIC_SUPABASE_ANON_KEY: Your Supabase anonymous key
```

### 2. EAS Configuration

```bash
# Login to EAS
eas login

# Initialize EAS project (if not already done)
eas build:configure

# Check your project configuration
eas project:info
```

### 3. Build Options

#### Option A: iOS Simulator (Quick Testing)
```bash
# Build for iOS Simulator (local build)
eas build --platform ios --profile development --local

# Install on simulator (macOS only)
# The .app file will be generated locally
```

#### Option B: iOS Device (TestFlight/Internal Testing)
```bash
# Build for iOS devices (cloud build)
eas build --platform ios --profile preview

# This creates an .ipa file that can be installed via TestFlight
```

#### Option C: Production Build
```bash
# Build for App Store submission
eas build --platform ios --profile production

# Submit to App Store
eas submit --platform ios --latest
```

## Build Profiles Explained

### Development Profile
- **Purpose**: Local testing and development
- **Target**: iOS Simulator
- **Bundle ID**: `com.ethiobook.mobile.dev`
- **Features**: 
  - Development client enabled
  - Fast rebuilds
  - Hot reloading support
  - Debug configuration

### Preview Profile
- **Purpose**: Internal testing and QA
- **Target**: Real iOS devices
- **Bundle ID**: `com.ethiobook.mobile.preview`
- **Features**:
  - TestFlight distribution
  - Staging environment
  - Release configuration
  - Internal testing features

### Production Profile
- **Purpose**: App Store release
- **Target**: End users
- **Bundle ID**: `com.ethiobook.mobile`
- **Features**:
  - App Store distribution
  - Production environment
  - Optimized build
  - Auto-increment versioning

## iOS Simulator Testing

### Prerequisites (macOS only)
```bash
# Install Xcode from App Store
# Open Xcode and install additional components
# Install iOS Simulator

# Verify installation
xcrun simctl list devices
```

### Building for Simulator
```bash
# Build locally for simulator
eas build --platform ios --profile development --local

# Wait for build to complete
# The .app file will be created in your project directory
```

### Installing on Simulator
```bash
# Start iOS Simulator
open -a Simulator

# Install the app
xcrun simctl install booted YourApp.app

# Launch the app
xcrun simctl launch booted com.ethiobook.mobile.dev
```

## Device Testing (TestFlight)

### 1. Apple Developer Setup
- Join Apple Developer Program
- Create App ID: `com.ethiobook.mobile`
- Configure capabilities (Push Notifications, etc.)
- Create provisioning profiles

### 2. EAS Credentials Setup
```bash
# Configure iOS credentials
eas credentials

# Follow the prompts to:
# - Upload certificates
# - Create/upload provisioning profiles
# - Set up push notification keys
```

### 3. Build and Distribute
```bash
# Build for devices
eas build --platform ios --profile preview

# Check build status
eas build:list

# Once complete, distribute via TestFlight
# The build will automatically appear in App Store Connect
```

## Using the Helper Scripts

### PowerShell Script (Windows)
```powershell
# Run the interactive menu
.\scripts\ios-test.ps1

# Or run specific actions
.\scripts\ios-test.ps1 -Action setup      # Environment setup
.\scripts\ios-test.ps1 -Action device     # Build for device
.\scripts\ios-test.ps1 -Action status     # Check build status
```

### Bash Script (macOS/Linux)
```bash
# Make executable
chmod +x scripts/ios-test.sh

# Run interactive menu
./scripts/ios-test.sh

# Script provides options for:
# - Building for simulator
# - Building for device
# - Checking build status
# - Installing on simulator
# - Configuring credentials
```

## Environment Variables

### Required Variables
```env
# EAS Configuration
EXPO_PROJECT_ID=your-eas-project-id

# App Environment
EXPO_PUBLIC_ENV=development
EXPO_PUBLIC_BUILD_NUMBER=1

# API Configuration
EXPO_PUBLIC_SUPABASE_URL=your-supabase-url
EXPO_PUBLIC_SUPABASE_ANON_KEY=your-supabase-anon-key

# Feature Flags
EXPO_PUBLIC_ANALYTICS_ENABLED=true
EXPO_PUBLIC_CRASHLYTICS_ENABLED=true
```

### Optional Variables
```env
# Apple Developer
APPLE_ID=your-apple-id
APPLE_TEAM_ID=your-team-id
APPLE_APP_SPECIFIC_PASSWORD=your-app-password

# Development URLs
EXPO_PUBLIC_DEV_API_URL=http://localhost:3000
EXPO_PUBLIC_STAGING_API_URL=https://staging-api.ethiobook.com
```

## Troubleshooting

### Common Issues

#### 1. Build Failures
```bash
# Clear EAS cache
eas build --platform ios --profile development --clear-cache

# Check build logs
eas build:list
# Click on the build to see detailed logs
```

#### 2. Provisioning Profile Issues
```bash
# Reset credentials
eas credentials --platform ios

# Manually configure profiles
# 1. Go to Apple Developer Portal
# 2. Create/download provisioning profiles
# 3. Upload via EAS credentials
```

#### 3. Certificate Problems
```bash
# Generate new certificates
eas credentials --platform ios

# Choose "Build credentials"
# Select "iOS Distribution Certificate"
# Follow prompts to generate/upload
```

#### 4. Simulator Installation Issues
```bash
# Reset simulator
xcrun simctl erase all

# Reinstall app
xcrun simctl uninstall booted com.ethiobook.mobile.dev
xcrun simctl install booted YourApp.app
```

### Getting Help

1. **EAS Build Logs**: Check detailed logs in EAS dashboard
2. **Expo Forums**: https://forums.expo.dev/
3. **Expo Discord**: https://chat.expo.dev/
4. **Apple Developer Support**: For iOS-specific issues

## Production Checklist

### Before App Store Submission
- [ ] Test on multiple iOS versions (iOS 13+)
- [ ] Test on different device sizes (iPhone, iPad)
- [ ] Verify all permissions and privacy descriptions
- [ ] Test offline functionality
- [ ] Performance testing
- [ ] Security review
- [ ] App Store metadata and screenshots
- [ ] Privacy policy and terms of service

### App Store Connect Setup
- [ ] Create app listing
- [ ] Upload screenshots
- [ ] Write app description
- [ ] Set pricing and availability
- [ ] Configure age rating
- [ ] Set app category
- [ ] Add app keywords

### TestFlight Testing
- [ ] Internal testing (team members)
- [ ] External testing (limited users)
- [ ] Gather feedback and fix issues
- [ ] Final testing before submission

## Next Steps

1. **Configure your EAS project ID** in `app.config.ts`
2. **Set up environment variables** in `.env`
3. **Run the setup script** to verify configuration
4. **Build for simulator** to test locally
5. **Build for device** to test on real hardware
6. **Submit for TestFlight** for broader testing
7. **Submit to App Store** for production release

## Support

For EtBook-specific issues:
- Check the main README.md
- Review the comprehensive testing documentation
- Contact the development team

For iOS/EAS issues:
- Expo documentation: https://docs.expo.dev/
- EAS Build documentation: https://docs.expo.dev/build/introduction/


