package api

// AppVersion is the canonical application version.
// Scheme: MAJOR.MINOR.PATCH[-PRERELEASE]
//   MAJOR 0  — pre-1.0; not yet in official production release
//   MINOR    — increments with each feature milestone
//   PATCH    — increments for bug-fix-only drops
//   PRERELEASE — alpha.N → beta.N → rc.N (dropped on stable release)
const AppVersion = "0.2.0-alpha.1"
