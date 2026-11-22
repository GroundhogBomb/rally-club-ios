# Rally Club handoff

R1 covers the Rally Club identity, English interface, fictional demo data, and replacement artwork. The implementation and verification record is in [EXECUTION_LOG.md](EXECUTION_LOG.md). The maintenance points and asset specifications are in [MAINTENANCE_MAP.md](MAINTENANCE_MAP.md) and [DESIGN_ASSETS.md](DESIGN_ASSETS.md).

Boom accepted S1 through S4. S3 introduced AsyncStream multicast and Observation for the three community stores. See the [S3 evidence](Evidence/S3/) and [execution log](EXECUTION_LOG.md). S4 creates one set of stores per session and migrates the pending photo queue to GRDB. See the [migration guide](MIGRATION.md), [S4 evidence](Evidence/S4/), and [execution log](EXECUTION_LOG.md). R1.1 removed the Club tab and its flyer book, so the S5 page-curl migration is canceled. S6 removes the alternate appearance and its UIKit bridges. Boom owns independent S6 acceptance. [Release comparison screenshots](Evidence/S6/)

R1.2 uses English for demo posts, game requests, and announcements. Debug and Release builds, the working-tree leak scan, and the Release demo walkthrough passed. The [R1.2 evidence](Evidence/R1.2/) covers the entry, four tabs, a published post, and a new game request. R1.2 was committed as `aae7944`.

S1 migrates the live court map to SwiftUI Map and adds Swift Testing and XCTest UI targets. The test and simulator results are recorded in [EXECUTION_LOG.md](EXECUTION_LOG.md).

S2 replaces embedded web playback for feed GIFs and adds decoder and post-display tests to the existing test targets. See [EXECUTION_LOG.md](EXECUTION_LOG.md) for the build and test record.
