# Build and sign

Three signing paths, one agent rule: **do not touch them.** Read this to explain
what a build's `signature` line means, not to run the scripts.

## Signing, in preference order

1. **Explicit identity**: `--sign IDENTITY` / `SIGN_IDENTITY` env —
   `Scripts/build.sh:46,31,132-133`.
2. **Local certificate**, `Citlla E510 Local Signing`, in
   `~/Library/Keychains/citlla-signing.keychain-db`, password at
   `~/Library/Application Support/CitllaE510/signing/keychain-password` —
   `build.sh:72-74,134-142`.
3. **Ad hoc fallback**: `designated => identifier "com.ericng.citllae510"` —
   `build.sh:144-157`.

The designated requirement with the certificate is

```
identifier "com.ericng.citllae510" and certificate root = H"…"
```

so TCC treats the app as the same app across rebuilds, reinstalls and path
changes, and only binaries signed with that key match — `README.md:286-293`,
`PROGRESS.md:123-130`.

Ad hoc survives rebuilds too but is the weak form: **any** bundle claiming the
identifier matches — `README.md:298-302`. This was verified, not assumed: a copy
re-signed ad hoc with the same identifier reported `accessibilityTrusted: false`
under the certificate requirement, while an identical copy at a temp path stayed
`true` (`PROGRESS.md:134-139`).

## The certificate script

`Scripts/create-signing-identity.sh` creates a **10-year** self-signed
code-signing certificate in its own keychain; no-op if it exists —
`README.md:280-286`, `PROGRESS.md:119-122`. The certificate is deliberately
untrusted for Gatekeeper: the app is built locally and never quarantined, so
`spctl` rejecting it is expected (`README.md:294-296`).

Signing step only unlocks the keychain; it never touches TCC
(`PROGRESS.md:147-149`).

## What the build does

1. `xcodegen generate` when present — `build.sh:85`. Rewrites the committed
   pbxproj.
2. Tests in Debug into `build/DerivedData` — `build.sh:89-107`; the printed count
   comes from grepping the log.
3. Build the chosen configuration — `build.sh:110-128`; up to 5 warnings printed,
   never fatal (`:131`).
4. Sign — `build.sh:132-157`.
5. Verify the bundle — `build.sh:161+` (id, executable, version, `--verbose=4`
   signature, arch).
6. Install — `build.sh:190-226`; quits a running copy first, `ditto`, then
   `lsregister`.
7. Launch — `build.sh:229-232`.

`build/` is gitignored (`build/`, `DerivedData/` — `.gitignore:2-3`), so build
output never belongs in a commit.

## Entitlements

`CitllaE510/CitllaE510.entitlements` is an **empty dict** on 2026-11-11 — no
sandbox. Hardened runtime comes from the `--options runtime` flag at signing
(`build.sh:137-153`), not from an entitlement.

Consequence worth stating plainly: Accessibility and Input Monitoring are the
only gates on the event tap. There is no sandbox to constrain it, and no
entitlement to forget — so a `tccutil` reset is the whole recovery story.

## Verifying a bundle without installing

```bash
Scripts/check.sh --no-snapshots
codesign --verify --deep --strict build/DerivedData/Build/Products/Release/CitllaE510.app
codesign -dv --verbose=4 build/DerivedData/Build/Products/Release/CitllaE510.app
plutil -p build/DerivedData/Build/Products/Release/CitllaE510.app/Contents/Info.plist
```

`--verbose=4` is required to see `Authority` at all; the script notes that plain
`codesign -dv` made a certificate build look ad hoc (`build.sh:172-176`).

## Never

- Launch the built app. It installs a real session event tap and remaps the
  physical mouse.
- Create or import an identity, unlock a keychain, or pass `--sign`.
- Install (`--dest` still installs, just elsewhere).
- Run `tccutil reset …`.

See `permissions.md` for why the reset is a human step, and `decisions.md` for the
agent rule.
