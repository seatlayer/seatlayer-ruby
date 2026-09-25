# Releasing `seatlayer` to RubyGems

Releases are published by `.github/workflows/release.yml` through RubyGems
Trusted Publishing (OIDC). No API key is stored in this repository or in its
Actions secrets.

The gemspec sets `rubygems_mfa_required = "true"`, so a plain `gem push` asks for
an MFA code every time. Trusted Publishing satisfies that requirement without a
prompt, which is why releases go through the workflow.

## One-time setup

- The `seatlayer` gem on RubyGems lists this repository and `release.yml` as a
  trusted publisher.
- The publish job runs in the `rubygems` GitHub environment. Add required
  reviewers to that environment if a tag push should wait for approval.

## Release steps

1. Update `SeatLayer::VERSION` in `lib/seatlayer/version.rb`.
2. Add a dated entry at the top of `CHANGELOG.md`.
3. Run the gate locally:

   ```bash
   bundle install
   bundle exec rubocop
   bundle exec rspec
   ```

4. Merge the release commit to `main`, then tag it and push the tag:

   ```bash
   git tag v0.8.1 && git push origin v0.8.1
   ```

The workflow re-runs the gate, refuses to publish if the tag and
`SeatLayer::VERSION` disagree, builds the gem, checks that it contains only the
library files (no `spec/`, `.github/`, `Gemfile` or `.rubocop.yml`), and pushes it.

If the publish job fails after the tag exists, run the workflow manually
(`workflow_dispatch`) with the existing tag as `release_tag`.

## Verify

```bash
gem install seatlayer -v 0.8.1
ruby -e 'require "seatlayer"; puts SeatLayer::VERSION'
```

## If a release is wrong

RubyGems never accepts the same version twice.

- **Bad build:** `gem yank seatlayer -v <version>` and publish a patch version.
- **Leaked secret in an artifact:** yank it, then rotate the credential. Assume it
  was already mirrored.
