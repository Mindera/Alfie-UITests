# Alfie UI Tests

Automated UI tests for Alfie app using Maestro framework.

## Prerequisites

- Maestro installed ([Installation Guide](https://maestro.mobile.dev/getting-started/installing-maestro))
- For iOS:
  - Xcode and iOS Simulator
  - App bundle (.app) in artifacts folder
- For Android:
  - Android SDK and ADB
  - APK file in artifacts folder

## Project Structure

How to run tests by script:

1. Giving permission to run the script:
chmod +x scripts/run-tests.sh

2. Running the script:
./scripts/run-tests.sh {search yaml file path}