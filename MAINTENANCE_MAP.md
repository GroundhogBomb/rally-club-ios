# Rally Club maintenance map

| Maintenance point | Entry file |
| --- | --- |
| `AUTH-001` | `ProjectL/Models/AppSession.swift` |
| `BACKEND-001` | `ProjectL/Models/AppDataRepository.swift` |
| `BACKEND-DECODE-001` | `ProjectL/Models/SupabaseAppDataRepository.swift` |
| `CANVAS-001` | `ProjectL/Components/AppPalette.swift` |
| `CLUB-ANNOUNCEMENT-001` | `ProjectL/Models/ClubFeedStore.swift` |
| `CLUB-FEED-001` | `ProjectL/Models/ClubFeedStore.swift` |
| `COURT-DISCOVERY-001` | `ProjectL/Models/CourtDiscoveryModel.swift` |
| `COURT-MAP-001` | `ProjectL/Components/CourtMapView.swift` |
| `DEMO-DATA-001` | `ProjectL/Models/AppDataRepository.swift` |
| `FEED-GIF-001` | `ProjectL/Components/FeedMediaView.swift` |
| `GAME-REQUEST-001` | `ProjectL/Models/GameRequestStore.swift` |
| `I18N-001` | `ProjectL/Models/AppLanguage.swift` |
| `MATCH-MOMENT-PENDING-001` | `ProjectL/Models/SupabaseAppDataRepository.swift` |
| `NAV-001` | `ProjectL/Components/AppPalette.swift` |
| `PROFILE-001` | `ProjectL/Models/ProfileStore.swift` |
| `SESSION-REMINDER-001` | `ProjectL/Models/SessionReminderStore.swift` |
| `SUPABASE-REPOSITORY-001` | `ProjectL/Models/SupabaseAppDataRepository.swift` |
| `SUPPORT-001` | `ProjectL/Models/ProfileStore.swift` |
| `VERSION-GATE-001` | `ProjectL/Models/VersionGate.swift` |

`NAV-001` covers Courts, Feed, Training Lounge, and Me. `SUPPORT-001` opens an email draft for feedback.

`MATCH-MOMENT-PENDING-001` owns the GRDB schema, account-scoped photo queue, legacy JSON import, cleanup, and Debug contract check. [Migration and recovery](MIGRATION.md)

`BACKEND-001` owns the shared AsyncStream broadcaster. Each of the three community stores listens to its own stream and uses Observation to refresh repository-backed views. `SignedInStores` in `ProjectL/Views/RootTabView.swift` creates one repository and set of stores per signed-in session. `CLUB-FEED-001` owns publishing, the feed list, and the post count shown in Me.

`CANVAS-001` owns the static backdrop, standard palette, and backing materials. `ProjectL/App/ProjectL.swift` configures the two native segmented-picker fills at launch.
