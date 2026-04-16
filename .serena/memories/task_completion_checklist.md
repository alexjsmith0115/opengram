# Task Completion Checklist

1. **Build validates** — `xcodebuild -project OpenGram.xcodeproj -scheme OpenGram build` succeeds
2. **Tests pass** — `./scripts/test.sh` green; new bugfixes include regression test
3. **No partial work** — all call sites, tests, types updated in same change
4. **New files registered** — added to `project.pbxproj` (file ref + group + build phase)
5. **Manual visual validation** — use `computer-use` MCP to screenshot running app and verify UI
6. **No dead code** — removed unused imports, obsolete files, dead variables
7. **Lint/format** — no introduced warnings (Swift 6 strict concurrency)
