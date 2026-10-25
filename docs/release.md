# Release

Push to `main` with a `VERSION` that has no release yet → `release.yml` builds, signs, notarizes, publishes `ChargeKeeper-<version>.dmg` + `appcast.xml`, then updates the Homebrew cask.

## Former name (Jauge)

The app was renamed from Jauge (1.0.7 and earlier). What stays and what moves:

- Internal identifiers keep the old name so installs keep working: bundle ids `com.vlor999.jauge` and `com.vlor999.jauge.service`, daemon label and plist `com.vlor999.jauge.daemon`, `/var/run/jauge.sock`, `/Library/Application Support/Jauge`, `/var/log/jauge.log`, the PowerUI client name, the Sparkle key and its keychain account `jauge`. Changing one breaks existing installs.
- Old installs poll `https://github.com/Vlor999/jauge/releases/latest/download/appcast.xml`. GitHub redirects it to `Vlor999/chargekeeper` after the repository rename, as long as no new repository is created under the name `jauge`.
- Sparkle installs over the existing bundle path, so an updated install keeps the file name `Jauge.app` (`SUNormalizeInstalledApplicationName` is a build-time option of Sparkle, off in the release binary, and would take the name from the old bundle anyway). New installs get `ChargeKeeper.app`.
- The service program moved from `jaugectl` to `chargekeeperctl`. launchd keeps the old registration (and its `jaugectl` path) until reboot: after the update from Jauge, restart the Mac once.
- Homebrew: the cask is `chargekeeper`; `cask_renames.json` in the tap maps `jauge` to it.

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
hdiutil attach -nobrowse -readonly ChargeKeeper-*.dmg
spctl --assess --type execute -v /Volumes/ChargeKeeper/ChargeKeeper.app   # accepted, Notarized Developer ID
xcrun stapler validate /Volumes/ChargeKeeper/ChargeKeeper.app
hdiutil detach /Volumes/ChargeKeeper
```
