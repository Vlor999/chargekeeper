# Release

Push to `main` with a `VERSION` that has no release yet → `release.yml` builds, signs, notarizes, publishes `Jauge-<version>.dmg` + `appcast.xml`, then updates the Homebrew cask.

Never paste secret values (passwords, .p12, base64, keys) into a chat or a commit.

## Secrets

| Secret | Value |
|---|---|
| `APPLE_CERTIFICATE` | base64 of the Developer ID Application `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | `.p12` password |
| `APPLE_SIGNING_IDENTITY` | `Developer ID Application: Willem Adnet (4WTQGGKVHL)` |
| `APPLE_ID` | Apple ID email |
| `APPLE_PASSWORD` | app-specific password (account.apple.com > Sign-In and Security) |
| `APPLE_TEAM_ID` | `4WTQGGKVHL` |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key for updates (login keychain, account `jauge`) |
| `HOMEBREW_TAP_TOKEN` | optional, token with write access to `Vlor999/homebrew-tap` |

Same Apple values as pr-radar (see its `docs/apple-notarization.md`). Export the certificate again from Keychain Access (My Certificates > Developer ID Application > Export, `.p12`), then:

```sh
base64 -i DeveloperID.p12 | gh secret set APPLE_CERTIFICATE
gh secret set APPLE_CERTIFICATE_PASSWORD
gh secret set APPLE_SIGNING_IDENTITY
gh secret set APPLE_ID
gh secret set APPLE_PASSWORD
gh secret set APPLE_TEAM_ID
gh secret set HOMEBREW_TAP_TOKEN
rm DeveloperID.p12
```

Sparkle key, if it has to be set again:

```sh
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account jauge -x /tmp/ed.key
gh secret set SPARKLE_PRIVATE_KEY < /tmp/ed.key && rm /tmp/ed.key
```

The matching public key is `SUPublicEDKey` in `project.yml`. Losing the private key means existing installs can no longer verify updates.

## Rerun a release

```sh
gh workflow run release.yml
```

## Check a release

```sh
hdiutil attach -nobrowse -readonly Jauge-*.dmg
spctl --assess --type execute -v /Volumes/Jauge/Jauge.app   # accepted, Notarized Developer ID
xcrun stapler validate /Volumes/Jauge/Jauge.app
hdiutil detach /Volumes/Jauge
```
