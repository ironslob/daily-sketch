# TestFlight Upload Runbook

## Prerequisites (owner)

- Apple Developer Team ID in signing configuration
- App Store Connect app record
- Distribution certificate + App Store provisioning profile
- Release Staging or Release Production scheme selected

## Archive

1. `make ios-generate`
2. Open `ios/DailySketch.xcodeproj`
3. Select scheme **DailySketch**, configuration **Release-Staging**
4. Product → Archive
5. Validate archive
6. Distribute → App Store Connect → Upload

## Traceability

Record in App Store Connect release notes:

- iOS `MARKETING_VERSION` / build number
- Backend `/health/version` output from matching staging deploy
- Git commit SHA

## In-repo readiness

Configs, Privacy Manifest, and metadata templates are present. Live upload requires owner credentials and is not claimed by CI.
