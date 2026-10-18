# Mac library launch

## Symptom and target

The signed Mac Release app displayed an empty library after its eight-second scan deadline. The saved security-scoped vault bookmark resolved. The target is to display the existing vault within that budget.

## Baseline

The same MacBook Pro vault has 1,181 Markdown files in 17 folders. A filesystem metadata walk takes 0.002 seconds. The package metadata loader takes 0.082 seconds. Its first three coordinated prefix reads take 0.7085, 0.6976, and 0.6998 seconds. The full original probe was stopped after 76 seconds without a result. No complete baseline duration is claimed.

The production app is Release. The read-only package probes are Debug and establish the repeated filesystem cost. They do not measure total native launch time.

## Cause and correction

The list snapshot performs a coordinated document read for every note before publishing any rows. Each file-provider coordination repeats the same delay. The snapshot now requests a best-effort local preview. It skips notes reported as not downloaded and retains their filename rows. Opening and editing a document keep the existing coordinated read and write paths.

## Measured result

The corrected package probe reads all 1,181 local previews in 3.078 seconds on the same Mac and vault. The final signed Release app is installed at /Applications/Noto.app. Independent read-only verification confirms a populated library and restored editor, without a timeout alert. A second capture five seconds later confirms the stable result.

## Regression protection

The primary new test fails with four issues on the previous code and passes after the correction. It models unavailable coordinated reads with readable local previews. Two additional tests preserve unavailable rows and enforce the byte limit. All 152 NotoVault tests and all 32 relevant Mac app tests pass after the final source edits.

## Boundaries

A list preview can briefly reflect an in-progress external edit. Later refreshes replace it. Full document operations retain coordination. The probe reads existing notes; it does not change note contents. No scrolling, frame-rate, power, or production iCloud sync claim is made.
