# Noto 0.2.0

Noto for Mac is 0.2.0 (202610181301). Noto 2 TestFlight is 0.2.0 (202610181312). The release combines the completed Mac redesign and five Noto 2 flows: Capture, Inbox, Library, Daily, and Search.

The desktop app remains Noto. Noto 2 remains the iOS app. The Mac app, Noto 2, and Noto 2 extensions use version 0.2.0. The separate original Noto iOS app retains version 1.0.

## Changes

The Mac has its new workspace, Capture, Inbox, palettes, inspector, and keyboard commands. Noto 2 has the five reviewed flows and shared filing sheets. The release includes the capture-routing and media dependencies already used by the verified candidate.

Mac signing selects a separate profile for the macOS SDK. The shared iOS App Store profile remains unchanged. The Mac profile uses the existing development certificate and includes both registered Macs, iCloud, and Associated Domains.

## Verification

Before release, Noto 2 passed 204 app cases. Its four relevant packages passed 374 cases. The candidate has identical package, test, and app source except removal of a trailing empty line in SearchScreen. Version and Mac signing settings also changed.

The desktop session passed 32 relevant Mac tests. Its final visual audit reports PARTIAL for proof limits, with no confirmed failures in 149 component rows. The release repeats all 32 Mac checks with zero failures. Its signed Mac Release bundle reports the intended version and build. All five compiled model files are present; the model weights match the verified source. Noto 2 also builds in Release for the iOS simulator, and both extensions report the same version and build.

## Known limits

The iOS Inbox drag cue can clip during a slow upward drag. The native Daily calendar is taller than the reference. Exact Mac font and colour identity, some native menu pixels, and production iCloud sync behavior remain outside the visual proof. Independent verification of the final installed Pro build confirms that the real library and restored editor load without the timeout.

The release request authorizes commits, installation on both desktops, and a Noto 2 TestFlight build. No push was requested. TestFlight upload and the canonical availability verification pass. Apple reports VALID on the highest train, 0.2.0, with internal state IN_BETA_TESTING. The IPA, app, and both extensions pass identity, version, build, distribution-signature, and model-weight checks. External beta submission was not requested. Both desktops now run the identical signed Mac bundle. The Air verification confirms all 23 bundle file hashes, the signature, the running application path, and the preserved 1.0 backup.

## Launch correction

The first production launch found a library timeout on the real 1,181-note vault. The final build uses local list previews and preserves coordinated document operations. The corrected package scan takes 3.078 seconds. Bug 043 and the performance note retain the failing launch and the regression evidence.

The Mac version uses an SDK-specific setting. The separate original Noto iOS version remains 1.0. The final 32 Mac checks and 152 NotoVault tests pass.
