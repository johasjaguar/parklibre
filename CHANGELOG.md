# Changelog

All notable changes to this project will be documented in this file.

## [0.5.0] - 2026-03-07
### Added
- New **"Navigate to next parking spot"** 1 tap button
- Navigation info banner with 20s timeout and manual close handling.
- SPDX-FileCopyrightText identifiers to all source files for license compliance.
### Changed
- **Repository Cleanup** before upload to Codeberg.
- Removed orphaned licenses, backups, and generated files.
- Corrected font license to OFL-1.1.

## [0.4.0] - 2026-03-05
### Added
- **Branding:** Integrated new logo design and free implementation of DIN 1451 Mittelschrift font.
### Fixed
- **UI UX:** Improved snackbar management by preventing stacking and increasing duration to 8s.
- Converted logo to proper PNG format.

## [0.3.0] - 2026-03-03
### Added
- **Global Search:** Implemented address search across all cities with automatic city switching.
- Added `proj4dart` dependency for advanced coordinate transformations.
### Fixed
- **Dresden:** Significant improvements to reverse geocoding (PLZ, district, and city parsing).
- **UX:** Added filter button locking during data fetch and reliable clearing of old error messages.
- **Startup:** Fixed race condition where parking spots loaded before city initialization was complete.

## [0.2.0] - 2026-03-02
### Added
- **Multi-city Support:** Integrated Munich and Dresden (via OGC API).
### Fixed
- Map centering: Now automatically zooms to city center upon city switch.
- Stability: Resolved `ClientException` on city switch by implementing a shared HTTP client.
- Fixed Berlin marker coordinates.

## [0.1.0] - 2026-03-01
### Added
- **Initial Release:** ParkLibre base version for Berlin.
- Radius filter with address autocomplete and camera animations.
- Detailed parking spot info sheets with external navigation intent handling.
- Map stability: Disabled gesture rotation for improved usability.
