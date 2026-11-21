# Vendored packages

Local copies of the speech packages used by the Listening tab.

| Package | Upstream | Version | License |
| --- | --- | --- | --- |
| KokoroSwift | https://github.com/mlalma/kokoro-ios | 1.0.11 (4d6d1d8) | MIT |
| MisakiSwift | https://github.com/mlalma/MisakiSwift | 1.0.6 (6835a1c) | Apache-2.0 |

## Changes from upstream
- Resources moved from `Resources/` at the package root into the target (`KokoroResources/`, `MisakiResources/`),
  and the `Bundle.module` lookups follow the new folder name. Upstream copies a folder named `Resources` into the
  resource bundle, which makes code signing fail for iOS Simulator builds ("bundle format unrecognized").
- mlx-swift raised from 0.30.2 to 0.33.0. With 0.30.2 the iOS Simulator build fails to link Cmlx
  (`MTLIOErrorDomain` and `MTLTensorDomain` are missing from the simulator SDK).
- KokoroSwift depends on the local MisakiSwift.
- Test targets removed.
