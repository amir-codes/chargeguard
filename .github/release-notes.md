## Install

**Download** `ChargeGuard.dmg` below, open it and drag ChargeGuard to Applications.

ChargeGuard is ad-hoc signed and not notarized by Apple (that needs a paid Developer ID), so macOS asks
once before the first launch:

1. Open ChargeGuard and close the warning.
2. Open **System Settings → Privacy & Security** and click **Open Anyway** next to ChargeGuard, then
   confirm with your password. The button shows for about an hour after the first attempt.

Or remove the download flag in Terminal: `xattr -dr com.apple.quarantine /Applications/ChargeGuard.app`

**Or install from Terminal** (downloads this release, checks the checksum, installs, no warning):

```sh
curl -fsSL https://raw.githubusercontent.com/amir-codes/chargeguard/main/scripts/install.sh | bash
```

**Check the download** (optional): put both files in one folder and run
`shasum -a 256 -c ChargeGuard.dmg.sha256`.

Requires an Apple silicon MacBook with macOS 14 or later. The app is built from this repository's source by
the `Release` workflow on a GitHub-hosted Mac; the run that built it is linked from the Actions tab.

If charging ever looks wrong: **Restore normal charging** in the menu, `chargectl restore`, or restart the
Mac. See [SAFETY.md](https://github.com/amir-codes/chargeguard/blob/main/docs/SAFETY.md).
