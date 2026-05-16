# TestFlight via Fastlane and Match

This repo now has a first-pass Fastlane lane and a GitHub Actions workflow for TestFlight uploads.

## Workflow

- Trigger: push to `main` or manual `workflow_dispatch`
- Runner: `macos-26`
- Lane: `bundle exec fastlane ios deploy_testflight`
- Signing: `match(type: "appstore", readonly: true)`
- Upload: `upload_to_testflight` with App Store Connect API key auth

## Required GitHub Secrets

- `APP_IDENTIFIER`: can also be configured as a GitHub variable
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64`: base64-encoded `.p8` key content
- `DEVELOPER_TEAM_ID`
- `MATCH_GIT_URL`
- `MATCH_PASSWORD`
- `MATCH_GIT_BASIC_AUTHORIZATION`: base64 of `github_username:personal_access_token` for the match repo, unless you switch to SSH/deploy-key access

## Optional GitHub Variables

- `MATCH_GIT_BRANCH`: defaults to `main`

## Local Smoke Test

Run this after exporting the same env vars locally:

```sh
bundle exec fastlane --env local ios verify_app_store_record
bundle exec fastlane --env local ios bootstrap_match
bundle exec fastlane --env local ios deploy_testflight
```

For a non-upload signing check after bootstrapping, run match directly:

```sh
bundle exec fastlane --env local match appstore --readonly
```

## Notes

- The lane changes code-signing settings inside the CI checkout before archiving, so it should not dirty local project files unless `CI` is set.
- The App Store Connect app record must already exist. The current API key can upload builds but cannot create the app record.
- `match` is read-only in CI. Create or refresh certificates and profiles outside this workflow first.
- The App Store Connect API key is used for both `match` and TestFlight upload.

## References

- Fastlane `app_store_connect_api_key`: https://docs.fastlane.tools/actions/app_store_connect_api_key/
- Fastlane `match`: https://docs.fastlane.tools/actions/match/
- Fastlane `pilot` / `upload_to_testflight`: https://docs.fastlane.tools/actions/pilot/
- GitHub Ruby setup guidance: https://docs.github.com/en/actions/tutorials/build-and-test-code/ruby
- GitHub runner images: https://github.com/actions/runner-images
