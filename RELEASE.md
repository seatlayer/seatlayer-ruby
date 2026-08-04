# Releasing `seatlayer` to RubyGems

Publishing checklist for the SeatLayer Ruby server SDK. This gem has **never been published** —
the first push permanently claims the name `seatlayer` on RubyGems.

Everything below has been validated locally except the steps marked
**[needs a live account]**, which cannot be run until the account exists.

---

## 1. What the owner must create first

### RubyGems account

| Item | Value |
|---|---|
| Registry | https://rubygems.org |
| Gem name | `seatlayer` — verified **unclaimed** as of 2026-08-04 |
| Account | A RubyGems account with **MFA enabled** — see the hard requirement below |

> **Name squatting is the one mistake nothing can undo.** RubyGems does not reassign names on
> request. If the sweep will be delayed, push a `0.0.0` placeholder to claim `seatlayer` now.

### ⚠ MFA is not optional for this gem

`seatlayer.gemspec` sets:

```ruby
spec.metadata["rubygems_mfa_required"] = "true"
```

This means **`gem push` is rejected outright unless the publishing account has MFA enabled at the
"UI and API" (or "UI and gem signin") level.** Enabling MFA only for web sign-in is not enough and
produces a confusing rejection at push time.

Set it at: RubyGems → *Edit Profile* → **Multifactor authentication** → level
**"UI and API"**. Save the recovery codes.

This is deliberate — the setting also stops anyone from pushing a future version of this gem
without MFA — but it must be done *before* the first push, not after.

### Credential: pick ONE of these two paths

#### Path A — API key (simplest; right for a manual first publish)

1. RubyGems → *Edit Profile* → **API Keys** → *New API key*.
2. Scopes: tick **`push_rubygem`** only. Do not grant `yank_rubygem`, `add_owner` or
   `index_rubygems` to a key you will paste into a shell — issue those separately if ever needed.
3. **First push only:** the gem does not exist yet, so the key cannot be scoped to a single gem.
   Leave it unscoped for the first push, then edit the key to scope it to **`seatlayer`** once the
   gem exists.
4. With MFA at "UI and API", `gem push` will additionally prompt for your **OTP code** each time.
   That is expected and cannot be bypassed — plan for an interactive terminal.

The key lands in `~/.gem/credentials` (mode 0600) after the first `gem signin`.

#### Path B — Trusted Publishing / OIDC (better long term; recommended once CI publishes)

RubyGems supports Trusted Publishing from GitHub Actions — no long-lived API key, and it
**satisfies the MFA requirement without an OTP prompt**, which is the main reason to prefer it here.

- Requires the GitHub repo `seatlayer/seatlayer-ruby` to **exist and be pushed** — it does not
  today (`git remote -v` points at it, but nothing has been pushed).
- For a gem that does not exist yet, configure a **pending trusted publisher**: RubyGems →
  *Trusted Publishers* → *Create*. You need: repository `seatlayer/seatlayer-ruby`, workflow
  filename (e.g. `release.yml`), optionally an environment name.
- The workflow needs `permissions: id-token: write` and `rubygems/release-gem@v1`.
- **No release workflow exists in this repo yet** — only `.github/workflows/ci.yml`. Writing it is a
  prerequisite for Path B.

**Recommendation:** use Path A for this first manual sweep, then move to Path B before 0.2.0 —
the OTP prompt makes Path A genuinely unpleasant to automate.

---

## 2. Pre-flight (all verified locally on 2026-08-04)

```bash
cd ruby
bundle install
bundle exec rubocop     # → 12 files inspected, no offenses detected
bundle exec rspec       # → 37 examples, 0 failures
```

Confirm before building:

- [ ] `CHANGELOG.md` top entry reads `## 0.1.0 — 2026-08-04`. **If the sweep has slipped past that
      date, change it** — `changelog_uri` is shown on the RubyGems page.
- [ ] `lib/seatlayer/version.rb` reads `0.1.0`.
- [ ] Working tree is clean and the release commit is tagged (`git tag v0.1.0`).

---

## 3. Build and inspect

```bash
rm -f *.gem
gem build seatlayer.gemspec
```

The gem must contain **exactly** these ten files:

```
CHANGELOG.md  LICENSE  README.md
lib/seatlayer.rb
lib/seatlayer/{errors,http_client,inventory,resources,version,webhook}.rb
```

Verify — the `files` list is explicit globs, never `git ls-files`, so `spec/`, `.github/`,
`.rubocop.yml`, `Gemfile` and `AGENTS.md` stay out:

```bash
tar -xOf seatlayer-0.1.0.gem data.tar.gz | tar tz     # 10 entries, no spec/, no AGENTS.md
gem specification seatlayer-0.1.0.gem                 # eyeball metadata URIs
```

Check the metadata block reads:

```yaml
homepage_uri: https://seatlayer.io
documentation_uri: https://docs.seatlayer.io/server-sdk/install/
source_code_uri: https://github.com/seatlayer/seatlayer-ruby
changelog_uri: https://github.com/seatlayer/seatlayer-ruby/blob/main/CHANGELOG.md
bug_tracker_uri: https://github.com/seatlayer/seatlayer-ruby/issues
rubygems_mfa_required: 'true'
```

---

## 4. Publish

There is no TestPyPI equivalent for RubyGems. The nearest rehearsal is a local install from the
built `.gem` (step 5 does exactly this) — do that before pushing, because the push is final.

```bash
gem signin              # once per machine; stores ~/.gem/credentials
gem push seatlayer-0.1.0.gem
# → prompts for your MFA OTP code
```

Then push the tag:

```bash
git push origin main --tags
```

---

## 5. Verify the published gem

Install into a throwaway `GEM_HOME` so nothing touches the system gems:

```bash
export GEM_HOME=/tmp/verifygems GEM_PATH=/tmp/verifygems
gem install seatlayer          # must resolve from RubyGems, not a local .gem
ruby -e '
  gem "seatlayer"; require "seatlayer"
  puts SeatLayer::VERSION
  c = SeatLayer::Client.new("sk_test_x")
  puts c.mode
  puts %i[charts events inventory sessions webhooks workspaces].all? { |m| c.respond_to?(m) }
'
```

Expected: `0.1.0`, `test`, `true`.

Also eyeball https://rubygems.org/gems/seatlayer for:

- README rendering
- **MIT** licence
- The sidebar links: Homepage, Documentation, Changelog, Source Code, Bug Tracker
- "Required Ruby Version: >= 3.0.0"
- No runtime dependencies listed

---

## 6. If it goes wrong

**RubyGems does not allow re-pushing a version.** Once `0.1.0` is up, that version number is spent
— yanking does not free it for re-upload.

| Situation | Action |
|---|---|
| Bad gem, caught fast | `gem yank seatlayer -v 0.1.0` — removes it from the index so `gem install seatlayer` stops resolving to it. Anyone who already installed it keeps it. This is the correct, non-destructive fix. |
| Need a fixed build out | Bump to `0.1.1` and push that. A yanked version number **cannot be reused**, even after yanking. |
| Leaked secret in the gem | Yank immediately, then rotate the credential. The gem was public and mirrored — yanking is not containment. |
| Wrong gem entirely | Yank every version. The **name stays yours** (yanked gems keep their name reserved), so this does not free `seatlayer` for someone else — but it also does not let you start over at `0.1.0`. |

`gem yank` needs an API key with the **`yank_rubygem`** scope, which the push-only key from Path A
deliberately does not have. Issue a separate yank key if you need one — and note you will not want
to be creating it under time pressure, so consider creating it during the sweep and storing it.

---

## 7. Post-publish

- [ ] Scope the API key to the `seatlayer` gem now that it exists (Path A step 3).
- [ ] Consider a `release.yml` + Trusted Publishing (Path B) before 0.2.0 — it removes the OTP
      prompt, which is the main obstacle to automating this.
- [ ] `required_ruby_version` is `>= 3.0.0` and CI tests 3.0. Ruby 3.0 has been EOL since 2024. The
      code is stdlib-only so the claim holds, but consider raising the floor to 3.1 at 0.2.0 rather
      than advertising support for an unpatched runtime.
- [ ] Fleet nit, not a blocker: the `User-Agent` is the bare string `seatlayer-ruby` with no version,
      matching node/go/php/python. Once these are in customers' hands, support cannot tell which SDK
      version a request came from. Worth changing across all seven at once, never in one.
