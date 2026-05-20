# Releasing OutOfRange

This project uses the BigWigs packager via GitHub Actions to build and upload
zips to CurseForge, Wago, and GitHub Releases automatically whenever you push
a version tag. After the one-time setup below, every release is two
commands.

## One-time setup

### 1. Create the projects

Go to **CurseForge** and **Wago**, sign in, and create a new addon project for
OutOfRange on each.

- CurseForge: https://www.curseforge.com/wow/addons → "Upload an addon"
- Wago: https://addons.wago.io/ → "Create"

You don't need to upload a zip yet — just claim the project name and let it
sit empty. The first GitHub Actions release will populate it.

### 2. Grab the project IDs and add them to the TOC

After creating each project, copy:

- **CurseForge Project ID** — visible in the upper-right of the project page,
  near the title. Numeric, like `123456`.
- **Wago Project ID** — visible in the project's "Tools" page. Looks like
  `LbN39A2k`.

Add two lines to `OutOfRange.toc` near the top:

```
## X-Curse-Project-ID: 123456
## X-Wago-ID: LbN39A2k
```

These let the CurseForge / Wago client apps recognize installed copies and
auto-update them. Optional but expected.

### 3. Create API tokens

Both sites support API tokens for the packager to upload on your behalf.

- **CurseForge API key**: https://legacy.curseforge.com/account/api-tokens →
  "Generate a New Token". Copy the long string.
- **Wago API token**: https://addons.wago.io/account/apikeys → "Create API
  Key" → copy the value.

### 4. Add the tokens as GitHub secrets

In your GitHub repo: **Settings → Secrets and variables → Actions → New
repository secret**. Add two:

- Name: `CF_API_KEY`        Value: your CurseForge token
- Name: `WAGO_API_TOKEN`    Value: your Wago token

(`GITHUB_TOKEN` is provided automatically by GitHub Actions; don't add it
manually.)

### 5. Push the repo to GitHub

```
git init
git add .
git commit -m "Initial commit: v1.10.2"
git branch -M main
git remote add origin git@github.com:WowDonf/OutOfRange.git
git push -u origin main
```

## Releasing a new version

Three steps:

1. **Bump the version.** Edit `## Version:` in `OutOfRange.toc` and add a new
   entry at the top of `CHANGELOG.md` describing what changed.

2. **Commit and tag.** The tag name must start with `v` to trigger the
   workflow:

   ```
   git add OutOfRange.toc CHANGELOG.md
   git commit -m "Release v1.10.3"
   git tag v1.10.3
   git push && git push --tags
   ```

3. **Watch the build.** Open the Actions tab on GitHub. The `Release`
   workflow should run in 1–2 minutes. When it goes green:

   - The CurseForge project page shows the new file.
   - The Wago project page shows the new file.
   - GitHub Releases has the zip as an asset on the `v1.10.3` tag.

No manual zip uploads, no manual library updates — the packager fetches the
latest LibStub / LibDBIcon / etc. from upstream every release.

## Test runs without releasing

To dry-run the build locally before tagging, install the packager:

```
curl -s https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh | bash
```

Then run it from the repo root. It will produce a zip in `.release/` without
uploading anywhere.

## Troubleshooting

- **The workflow ran but nothing appeared on CurseForge.** Double-check
  `CF_API_KEY` is set in GitHub repo secrets, and that the CurseForge project
  ID in `OutOfRange.toc` matches the project. The packager uses the ID, not
  the project name.
- **"Could not find a TOC file"** — the packager expects `OutOfRange.toc` at
  the repo root. Don't nest the addon inside a subfolder.
- **A library failed to fetch from SVN.** Rare, but the WoWAce/CurseForge SVN
  occasionally has outages. Re-running the workflow usually fixes it.
- **Tag pushed but workflow didn't trigger.** Tag must start with `v`
  (lowercase). And it must be pushed with `git push --tags`, not just
  `git push`.
