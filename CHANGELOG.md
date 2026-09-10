# Changelog

## [0.3.0] - 2026-09-11
### Changed
- **Breaking:** `set_boot_override` and the `boot_to_*` helpers take
  `persistence:` instead of `enabled:`. (#1, thanks @davispuh)
- Requires idrac >= 0.11.0 and radfish >= 0.3.0, which is where the matching
  `persistence:` signatures live. An older client gem can no longer resolve
  against this adapter.
- Documented what `set_one_time_cd_boot` and `wait_config_job` do. (#3)

### Added
- CI on push and pull request, and a release workflow publishing to RubyGems
  through trusted publishing (OIDC).
