#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/native
xcrun clang -mmacosx-version-min=14.0 -O2 -fmodules -DMAX_DISPLAYS=32 -I Vendor/m1ddc/headers \
 Native/DisplayBridge.m Vendor/m1ddc/sources/ioregistry.m \
 -framework Foundation -framework IOKit -framework CoreGraphics -framework CoreDisplay \
 -o .build/native/DisplayBridge
xcrun clang -Wall -Wextra Native/DDCProtocolTests.c -o .build/native/ddc-protocol-tests
.build/native/ddc-protocol-tests

xcrun clang -Wall -Wextra Native/ControlSafetyTests.c -o .build/native/control-safety-tests
.build/native/control-safety-tests

xcrun clang -mmacosx-version-min=14.0 -O2 -fobjc-arc -fmodules Native/ConnectionProbe.m -framework Foundation -framework CoreGraphics -framework CoreDisplay -o .build/native/ConnectionProbe
