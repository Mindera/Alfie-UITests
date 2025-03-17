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
    local booted_device
    booted_device=$(xcrun simctl list devices | grep "Booted" | head -n 1 | awk -F "[()]" '{print $2}')
    
    if [ -z "$booted_device" ]; then
        echo "No simulator running. Creating and booting a new one..."
        
        # Get latest iOS runtime
        RUNTIME=$(xcrun simctl list runtimes | grep iOS | tail -n1 | cut -d ' ' -f7)
        
        # Create iPhone 16 simulator if it doesn't exist
        DEVICE_NAME="iPhone 16"
        DEVICE_ID=$(xcrun simctl list devices | grep "$DEVICE_NAME" | head -n1 | awk -F "[()]" '{print $2}')
        
        if [ -z "$DEVICE_ID" ]; then
            echo "Creating new $DEVICE_NAME simulator..."
            DEVICE_ID=$(xcrun simctl create "$DEVICE_NAME" "com.apple.CoreSimulator.SimDeviceType.iPhone-14" "$RUNTIME")
        fi
        
        echo "Booting simulator $DEVICE_ID..."
        xcrun simctl boot "$DEVICE_ID"
        
        # Wait for simulator to be ready
        echo "Waiting for simulator to be ready..."
        sleep 5
        
        # Enable keyboard
        xcrun simctl keyboard "$DEVICE_ID" sysdiagnose
        
        echo "✅ Simulator ready: $DEVICE_NAME ($DEVICE_ID)"
    else
        echo "✅ Found booted simulator: $booted_device"
    fi
    return 0
}

# Function to check Android device
check_android_device() {
    local device_id
    device_id=$(adb devices | grep -v "List" | grep "device$" | head -n 1 | cut -f1)
    
    if [ -z "$device_id" ]; then
        echo "No emulator running. Creating and starting a new one..."
        
        # Check if AVD exists
        if ! avdmanager list avd | grep -q "test_device"; then
            echo "Creating new emulator..."
            echo "y" | sdkmanager "system-images;android-31;google_apis;x86_64"
            echo "no" | avdmanager create avd -n test_device -k "system-images;android-31;google_apis;x86_64"
        fi
        
        # Start emulator in background
        echo "Starting emulator..."
        $ANDROID_HOME/emulator/emulator -avd test_device -no-audio -no-window &
        
        # Wait for device to be ready
        echo "Waiting for emulator to be ready..."
        adb wait-for-device
        
        # Additional wait to ensure device is fully booted
        sleep 10
        
        device_id=$(adb devices | grep -v "List" | grep "device$" | head -n 1 | cut -f1)
        echo "✅ Emulator ready: $device_id"
    else
        echo "✅ Found Android device: $device_id"
    fi
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

# Run tests with explicit output path
maestro test --env APP_ID="$APP_ID" --include-tags="$tag" tests/ --format=html --output="$report_file"