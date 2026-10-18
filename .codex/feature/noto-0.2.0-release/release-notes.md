# Noto 0.2.0

Build 202610181247 combines the completed Noto macOS redesign and the five Noto 2 flows: Capture, Inbox, Library, Daily, and Search.

The desktop app remains Noto. Noto 2 remains the iOS app. Both apps and Noto 2 extensions use version 0.2.0.

## Changes

The Mac has its new workspace, Capture, Inbox, palettes, inspector, and keyboard commands. Noto 2 has the five reviewed flows and shared filing sheets. The release includes the capture-routing and media dependencies already used by the verified candidate.

Mac signing selects a separate profile for the macOS SDK. The shared iOS App Store profile remains unchanged. The Mac profile uses the existing development certificate and includes both registered Macs, iCloud, and Associated Domains.

## Verification

Before release, Noto 2 passed 204 app cases. Its four relevant packages passed 374 cases. The candidate has identical package, test, and app source except removal of a trailing empty line in SearchScreen. Version and Mac signing settings also changed.

The desktop session passed 32 relevant Mac tests. Its final visual audit reports PARTIAL for proof limits, with no confirmed failures in 149 component rows. The release repeats all 32 Mac checks with zero failures. Its signed Mac Release bundle reports the intended version and build. All five compiled model files are present; the model weights match the verified source. Noto 2 also builds in Release for the iOS simulator, and both extensions report the same version and build.

## Known limits

The iOS Inbox drag cue can clip during a slow upward drag. The native Daily calendar is taller than the reference. Exact Mac font and colour identity, some native menu pixels, and production iCloud behavior remain outside the visual proof.

The release request authorizes commits and installation on the two desktops. It does not request a push or TestFlight upload.
