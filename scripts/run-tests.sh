#!/bin/bash

# Check if required arguments were provided
if [ $# -lt 2 ]; then
    echo "How to Run: ./run-tests.sh <platform> <tag>"
    echo "Example: ./run-tests.sh ios searchTests"
    echo "Available tags:"
    echo "  - searchTests : Search functionality tests"
    exit 1
fi

platform=$1
tag=$2

# Function to check iOS device
check_ios_simulator() {
    echo "Setting up 3 simulators..."
    local RUNTIME=$(xcrun simctl list runtimes | grep iOS | tail -n1 | cut -d ' ' -f7)
    local simulators=()
    
    # Create and boot 3 simulators
    for i in {1..3}; do
        DEVICE_NAME="iPhone 15 Test $i"
        DEVICE_ID=$(xcrun simctl create "$DEVICE_NAME" "com.apple.CoreSimulator.SimDeviceType.iPhone-15" "$RUNTIME")
        echo "Created simulator $i: $DEVICE_ID"
        
        xcrun simctl boot "$DEVICE_ID"
        echo "Booting simulator $i..."
        
        # Wait for simulator to be ready
        until xcrun simctl list devices | grep -q "$DEVICE_ID.*Booted"; do
            echo "Waiting for simulator $i to boot..."
            sleep 2
        done
        
        # Install app on each simulator
        xcrun simctl install "$DEVICE_ID" "$APP_PATH"
        simulators+=("$DEVICE_ID")
    done
    
    echo "✅ All simulators ready: ${simulators[*]}"
    return 0
}

# Function to check Android device
check_android_device() {
    echo "Setting up 3 emulators..."
    local emulators=()
    
    for i in {1..3}; do
        local avd_name="test_device_$i"
        
        # Create AVD if it doesn't exist
        if ! avdmanager list avd | grep -q "$avd_name"; then
            echo "Creating new emulator $i..."
            echo "y" | sdkmanager "system-images;android-31;google_apis;x86_64"
            echo "no" | avdmanager create avd -n "$avd_name" -k "system-images;android-31;google_apis;x86_64"
        fi
        
        # Start emulator in background
        echo "Starting emulator $i..."
        $ANDROID_HOME/emulator/emulator -avd "$avd_name" -no-audio -no-window &
        
        # Wait for device to be ready
        adb wait-for-device
        
        # Get device ID
        local device_id=$(adb devices | grep -v "List" | grep "device$" | tail -n1 | cut -f1)
        emulators+=("$device_id")
        
        # Install app on each emulator
        adb -s "$device_id" install "$APK_PATH"
    done
    
    echo "✅ All emulators ready: ${emulators[*]}"
    return 0
}

# Function to check if artifacts directory exists
check_artifacts_dir() {
    local artifacts_dir="artifacts"
    
    # Search for artifacts directory up to 3 levels up
    for i in . .. ../.. ../../..; do
        if [ -d "$i/$artifacts_dir" ]; then
            echo "✅ Found artifacts directory at: $i/$artifacts_dir"
            ARTIFACTS_PATH="$i/$artifacts_dir"
            return 0
        fi
    done
    
    echo "❌ Error: Could not find 'artifacts' directory"
    exit 1
}

# Find artifacts directory
check_artifacts_dir

# Configure platform and check installation
if [ "$platform" = "ios" ]; then
    APP_ID="com.mindera.alfie.debug"
    APP_PATH="$ARTIFACTS_PATH/Alfie.app"
    
    # Check simulator
    check_ios_simulator
    
    # Check if app exists in artifacts
    if [ ! -d "$APP_PATH" ]; then
        echo "❌ Error: iOS app not found at $APP_PATH"
        exit 1
    fi
    
    # Check if app is already installed
    if ! xcrun simctl list apps | grep -q "$APP_ID"; then
        echo "📱 App not installed. Installing iOS app..."
        xcrun simctl install booted "$APP_PATH"
        if [ $? -eq 0 ]; then
            echo "✅ iOS app installed successfully"
        else
            echo "❌ Error installing iOS app"
            exit 1
        fi
    else
        echo "✅ iOS app already installed"
    fi

elif [ "$platform" = "android" ]; then
    APP_ID="au.com.alfie.ecomm.debug"
    APK_PATH="$ARTIFACTS_PATH/Alfie.apk"
    
    # Check Android device
    check_android_device
    
    # Check if APK exists
    if [ ! -f "$APK_PATH" ]; then
        echo "❌ Error: Android APK not found at $APK_PATH"
        exit 1
    fi
    
    # Check if app is already installed
    if ! adb shell pm list packages | grep -q "$APP_ID"; then
        echo "📱 App not installed. Installing Android app..."
        adb install "$APK_PATH"
        if [ $? -eq 0 ]; then
            echo "✅ Android app installed successfully"
        else
            echo "❌ Error installing Android app"
            exit 1
        fi
    else
        echo "✅ Android app already installed"
    fi

else
    echo "❌ Invalid platform. Use 'ios' or 'android'"
    exit 1
fi

# Run tests
echo "🚀 Running tests for $platform..."
echo "🏷️  Running tests with tag: $tag"
echo "🆔 App ID: $APP_ID"

# Generate timestamp for report file
timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
report_file="reports/${timestamp}-report.html"

# Run tests with shard split
maestro test \
  --env APP_ID="$APP_ID" \
  --include-tags="$tag" \
  --format=html \
  --output="$report_file" \
  --shard-split 3 \
  tests/