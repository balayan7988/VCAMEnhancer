# VCAMEnhancer

TrollFools standalone dylib. Adds a floating `调` button and runtime post-processing controls for VCAM-like camera replacement dylibs.

## Features
- Brightness
- Contrast
- Saturation
- Gamma
- SoftLight center fill light
- Vignette
- Mirror

## Usage
TrollFools injection order:

1. Inject your base VCAM dylib, e.g. `VCAM_VPS_8099.dylib` or `jerryhook.dylib`
2. Inject `VCAMEnhancer.dylib`
3. Launch target app and tap floating `调` button.

Do not inject multiple base camera dylibs at the same time.
