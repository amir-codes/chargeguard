# Third-party notices

ChargeGuard is MIT licensed (see `LICENSE`). It adapts code or facts from the projects below. Their reference checkouts live in `references/` (git-ignored) and are never shipped.

## Code adapted (MIT)

### SMCKit

- Project: https://github.com/beltex/SMCKit
- License: MIT
- Used in: `Packages/ChargeGuardSystem/Sources/ChargeGuardSystem/AppleSMC.swift`
- What was adapted: the Swift layout of the AppleSMC `SMCKeyData_t` parameter struct, the selector values, and the key-info / read / write call sequence over `IOConnectCallStructMethod`. Changes: instance-based and thread-safe, `dataSize` declared as an explicit `UInt32` (SMCKit's `IOByteCount` is 8 bytes on arm64), a runtime layout check, `kIOMainPortDefault`, and errors mapped to `ChargeGuardCore.SMCError`.

```
The MIT License (MIT)

Copyright (c) 2014-2017  beltex <https://github.com/beltex>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

### battery (battery.sh)

- Project: https://github.com/actuallymentor/battery (battery.sh v1.3.4)
- License: MIT
- Used in: `Packages/ChargeGuardCore/Sources/ChargeGuardCore/SMC/SMCKeys.swift` (key and value table) and `Packages/ChargeGuardCore/Sources/ChargeGuardCore/SMC/KeyProbe.swift` (presence detection by reading each key, "no data" means absent)
- What was adapted: the SMC key names and byte values for blocking charging (`CHTE` 01000000/00000000, `CH0B` and `CH0C` 02/00), forcing discharge (`CHIE` 08/00, `CH0J` 01/00, `CH0I` 01/00), the MagSafe LED (`ACLC` 03 green, 04 orange, 01 off, 00 system default, marked unconfirmed upstream), the key preference order, the battery CLI's install folder and LaunchAgent label for conflict detection.

```
MIT License

Copyright (c) 2022 Mentor Palokaj

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Read only, no code copied (GPL)

These projects were read for facts and design ideas. No source code, comments or text from them is included in ChargeGuard.

### batt

- Project: https://github.com/charlie0129/batt
- License: GPL-2.0
- Facts used: the firmware charge-limit keys `bfF0` (activation, 00 inactive / 02 active), `bfD0` (upper %) and `bfE0` (lower %), their little-endian ui32 encoding (80 % = 50 00 00 00) and the write order (bfF0=00, bfD0, bfE0, bfF0=02); the rule that a key with zero size counts as absent; the read-only telemetry key names `AC-W`, `PDTR` and `PPBR`; the launchd label `cc.chlc.batt` and Homebrew label `homebrew.mxcl.batt` for conflict detection.
- Ideas used: holding the limit by cutting the adapter when the charge keys are gated (AdapterCutoffBackend), a minimum hysteresis band for that mode, blocking charging before sleep, and a `pmset disablesleep` hold with a persisted snapshot so it can be restored after a crash.

### OpenDente

- Project: https://github.com/killerk3emstar/OpenDente
- License: GPL-3.0
- Used as a reference for the general shape of a SwiftUI menu bar app with an SMAppService daemon and XcodeGen. No code copied.

## Feature naming only

### AlDente

- Public README: https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring
- Only the public README was used, for the names of features. ChargeGuard is not affiliated with or endorsed by AppHouseKitchen. It contains no AlDente code, and does not use AlDente's name for itself, its icon or its screenshots. The AlDente app binaries were never disassembled, decompiled or analysed.
