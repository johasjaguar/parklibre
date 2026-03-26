#!/bin/bash
# Setup Umgebungsvariablen für Qt Android Build

export QT_ANDROID_ROOT=~/Qt/6.10.2/android_arm64_v8a
export ANDROID_SDK_ROOT=~/Android/Sdk
export ANDROID_NDK_ROOT=~/Android/Sdk/ndk/28.2.13676358
export PATH=$QT_ANDROID_ROOT/bin:$PATH

echo "Umgebungsvariablen gesetzt:"
echo "QT_ANDROID_ROOT: $QT_ANDROID_ROOT"
echo "ANDROID_SDK_ROOT: $ANDROID_SDK_ROOT"
echo "ANDROID_NDK_ROOT: $ANDROID_NDK_ROOT"
echo ""
echo "Verfügbare Tools:"
which qt-cmake && echo "✅ qt-cmake"
which androiddeployqt && echo "✅ androiddeployqt"
