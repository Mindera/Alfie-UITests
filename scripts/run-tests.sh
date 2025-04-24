#!/bin/bash

# Verificar argumentos
if [ $# -lt 2 ]; then
    echo "❌ Uso: $0 <platform> <tag> [options]"
    echo "   platform: ios ou android"
    echo "   tag: tag dos testes a serem executados (ex: searchTests)"
    echo "   options: opções adicionais"
    echo "      --skip-device-check: pula a verificação do dispositivo (útil quando o emulador já está em execução)"
    exit 1
fi

platform=$1
tag=$2
skip_device_check=false

# Verificar opções adicionais
for arg in "${@:3}"; do
    case $arg in
        --skip-device-check)
            skip_device_check=true
            ;;
    esac
done

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
            echo "y" | sdkmanager "system-images;android-31;google_apis;arm64-v8a"
            echo "no" | avdmanager create avd -n test_device -k "system-images;android-31;google_apis;arm64-v8a"
        fi
        
        # Start emulator with ARM configuration
        echo "Starting emulator..."
        $ANDROID_HOME/emulator/emulator \
            -avd test_device \
            -no-audio \
            -no-boot-anim \
            -no-window \
            -gpu swiftshader_indirect \
            -accel off &
        
        # Wait for device with increased timeout
        adb wait-for-device shell 'while [[ -z $(getprop sys.boot_completed) ]]; do sleep 1; done'
        
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
    
    # Check Android device only if not skipped
    if [ "$skip_device_check" = false ]; then
        check_android_device
    else
        echo "✅ Pulando verificação do dispositivo Android (--skip-device-check)"
    fi
    
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
#####
    # Iniciar o aplicativo antes de executar os testes
    echo "📱 Iniciando o aplicativo para verificar a estrutura da UI..."
    adb shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1
    sleep 5
    
    # Capturar a hierarquia de visualização para diagnóstico
    echo "🔍 Capturando hierarquia de visualização para diagnóstico..."
    mkdir -p reports/ui-dump
    adb shell uiautomator dump /sdcard/window_dump.xml
    adb pull /sdcard/window_dump.xml reports/ui-dump/
    
    # Procurar por elementos de pesquisa na hierarquia
    echo "🔍 Procurando elementos de pesquisa na hierarquia..."
    grep -i "search\|input\|edit" reports/ui-dump/window_dump.xml > reports/ui-dump/search_elements.txt
    
    # Configurar variáveis de ambiente para o Maestro
    export MAESTRO_DRIVER_STARTUP_TIMEOUT=120000
    export MAESTRO_DRIVER_INSTALL_TIMEOUT=120000
    export MAESTRO_STUDIO_DEBUG=true
#####
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

#####
# Run tests with explicit output path
# maestro test --env APP_ID="$APP_ID" --include-tags="$tag" tests/ --format=html --output="$report_file"
#####
# Run tests with explicit output path and additional options
maestro test --env APP_ID="$APP_ID" --include-tags="$tag" tests/ --format=html --output="$report_file" --debug-output=reports/debug --flatten-debug-output
#####