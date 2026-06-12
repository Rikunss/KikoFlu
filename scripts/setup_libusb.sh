#!/bin/bash
# Script to download and setup libusb for Android NDK integration
# Run from project root: bash scripts/setup_libusb.sh

set -e

LIBUSB_VERSION="1.0.27"
LIBUSB_DIR="android/app/src/main/jni/libusb"
LIBUSB_TAR="libusb-${LIBUSB_VERSION}.tar.bz2"
LIBUSB_URL="https://github.com/libusb/libusb/releases/download/v${LIBUSB_VERSION}/${LIBUSB_TAR}"

echo "==> Setting up libusb ${LIBUSB_VERSION} for Android NDK"

# Check for required tools
if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
    echo "ERROR: Need curl or wget"
    exit 1
fi

# Create libusb directory
mkdir -p "${LIBUSB_DIR}"

if [ -f "${LIBUSB_DIR}/CMakeLists.txt" ]; then
    echo "==> libusb already appears to be present at ${LIBUSB_DIR}"
    echo "    Delete it and re-run to re-download"
    exit 0
fi

# Download
echo "==> Downloading ${LIBUSB_URL}..."
if command -v curl &> /dev/null; then
    curl -L -o "/tmp/${LIBUSB_TAR}" "${LIBUSB_URL}"
else
    wget -O "/tmp/${LIBUSB_TAR}" "${LIBUSB_URL}"
fi

# Extract
echo "==> Extracting..."
tar xjf "/tmp/${LIBUSB_TAR}" -C "/tmp/"
cp -r "/tmp/libusb-${LIBUSB_VERSION}/"* "${LIBUSB_DIR}/"

# Clean up
rm -rf "/tmp/libusb-${LIBUSB_VERSION}" "/tmp/${LIBUSB_TAR}"

echo "==> libusb ${LIBUSB_VERSION} extracted to ${LIBUSB_DIR}"
echo ""
echo "    Next step: ensure your CMakeLists.txt has:"
echo "        add_subdirectory(jni/libusb)"
echo "        target_link_libraries(usb_dac_driver libusb-1.0)"
