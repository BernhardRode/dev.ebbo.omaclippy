# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0](https://github.com/BernhardRode/omaclippy/compare/omaclippy-v1.1.0...omaclippy-v1.2.0) (2026-08-23)


### Features

* bar widget to summon clippy ([3405344](https://github.com/BernhardRode/omaclippy/commit/3405344c7e50bb5a6895bc8d0b7e8eea650324a7))
* blink idly every few seconds ([ae62661](https://github.com/BernhardRode/omaclippy/commit/ae626615c48383ff5922dc838a9d506fbf2bf00e))
* bundle clippy.glb conditioned into a Qt Quick 3D scene ([81bb3cf](https://github.com/BernhardRode/omaclippy/commit/81bb3cf9234f4dfc641d188bb7451ade3496b812))
* canned quip bank with test coverage ([79e4ec0](https://github.com/BernhardRode/omaclippy/commit/79e4ec042c7b8301174fb638a1d73104f865c3c9))
* draggable panel with scroll-resize, multi-monitor parking and agent session lifecycle ([aca7b41](https://github.com/BernhardRode/omaclippy/commit/aca7b413650ab8d67b3f020f0db89f77b5f0a703))
* live 3D viewport with idle wobble, jump, blink and paper animations ([3dedef3](https://github.com/BernhardRode/omaclippy/commit/3dedef3f0e285e4290749a47cb09a494d43a010a))
* pass clicks through the empty corners around clippy ([1cc520c](https://github.com/BernhardRode/omaclippy/commit/1cc520c773670c2691fc89982376b0de938a2177))
* scaffold Omarchy plugin with manifest and licensing ([5eea4e6](https://github.com/BernhardRode/omaclippy/commit/5eea4e6d6159762bb5bd45dea71fec58acb65bae))

## [1.1.0] - 2026-08-23

### Added

- Idle blinking: Clippy now blinks every few seconds with randomized timing and the occasional double blink.

### Fixed

- Clicks in the empty corners around Clippy no longer get swallowed by the invisible layer surface; they pass through to whatever is underneath.

## [1.0.0]

Initial release: 3D Clippy companion for Omarchy with cursor gaze tracking, drag/resize, AI quips with offline fallback, paper kick/throw, and a maximized agent-terminal dock.
