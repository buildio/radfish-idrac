# Changelog

## [Unreleased]
### Added
- `clear_completed_jobs`, the safe queue hygiene `Radfish::Core::Jobs` has
  always declared and no adapter implemented. It deletes only the jobs that
  have FINISHED and returns the ids removed; a job that has not finished is
  never touched. `pending_config_jobs` exposes the read-only view of what is
  still holding the queue. Both need the idrac release that carries them.
  (#7)
- The iDRAC job-queue conflict (409 / LC068 "a configuration job is already
  scheduled", "the maximum number of jobs is reached") is now recovered HERE,
  not by callers: the commands that schedule a Lifecycle Controller config job
  run inside `with_job_queue_retry`, which frees the finished slots with
  `clear_completed_jobs` and runs the command once more. An application does
  not have to know the iDRAC has a job queue. A 409 that is not about the
  queue -- a power action answering "already in that state" -- is untouched,
  and if the retry hits the same conflict the caller gets the original error.
  (#7)
- `free_job_queue_slots!` frees slots without cancelling anything: a job that
  is Running is polled to a terminal state (`wait_config_job`, never a blind
  sleep -- a BIOS config job runs during the host's POST and takes minutes)
  and then cleared with the other finished jobs. A Scheduled job only runs at
  the next host boot, so it is neither waited on nor deleted. The poll budget
  is `job_queue_wait` (default 900s; pass `job_queue_wait: 0` to skip it).

### Changed
- Documented that `clear_jobs!` and `drain_pending_config_jobs!` are not queue
  hygiene: both cancel work that has not finished. Behaviour unchanged.

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
