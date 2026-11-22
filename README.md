# Rally Club

Rally Club is an iOS portfolio demo for finding courts, arranging games, sharing club updates, and setting weekly session reminders. The project pairs human direction and acceptance checks with AI-assisted implementation.

## Run the demo

1. Open `ProjectL.xcodeproj` in Xcode.
2. Choose the **ProjectL** scheme and an iPhone simulator, then run.
3. Select **Continue in demo mode**.

The demo opens by default when backend settings are empty. It uses fictional members, court locations, announcements, posts, and game requests. Feed posts, requests, and profile edits last for the session. Weekly reminders are saved on the device and use the system notification permission.

The four tabs are Courts, Feed, Training Lounge, and Me. Game requests are in Feed. Session reminders are available from a court's details and from Me. Training Lounge is a preview for a future feature.

## Project layout

SwiftUI views call feature stores that share one repository for the current session. Demo mode uses an in-memory repository. A separately configured Rally Club backend uses the Supabase repository. `Config/Supabase.example.xcconfig` shows the optional local settings. The interface and demo content are in English. New posts, comments, and game requests use the English language code. Club administrators edit one English announcement.

## Court map migration

The live court map uses iOS 17 SwiftUI Map so the map content and camera position are defined in the SwiftUI view. The camera target has a pure function that Swift Testing can exercise with coordinates alone. Highlighted courts use a 1.6 km span and nearby discovery uses a 10 km span around the user's location.

The marker callout uses a custom SwiftUI annotation for title, address, and accessibility identifiers. Rally Club now owns the callout layout and selection state. The live map still uses MapKit tiles and system location, while the demo draws its court map offline. [Apple's MapKit for SwiftUI session](https://developer.apple.com/videos/play/wwdc2023/10043/)

## Feed GIF playback

Feed GIFs use ImageIO for frame decoding and SwiftUI for playback. Removing WebKit avoids running a web view for each GIF and gives the app control over frame size, timing, and Reduce Motion. Remote GIFs share the photo loader's session and 8 MB file limit. Named bundled artwork can supply a GIF or a still image.

Rally Club downsamples frames to the display size and keeps up to 60 frames within a 24 MiB budget for retained frames. Long animations play their decoded opening frames, and large animations can use smaller thumbnails. Sources over 16 megapixels use the media failure indicator. Frame delays have a 20 ms minimum, with 100 ms used for missing or invalid values. Reduce Motion displays the first frame. [ImageIO thumbnail options](https://developer.apple.com/documentation/imageio/kcgimagesourcethumbnailmaxpixelsize)

## Repository change notifications

Each community store listens to its own AsyncStream on the main actor. This replaces Combine subscriptions with a Swift Concurrency task whose lifetime follows the store. Each stream keeps one pending change signal. Back-to-back writes can share a refresh because the stores read the latest state from the repository. Ended subscriptions release their continuations. [Swift AsyncStream documentation](https://developer.apple.com/documentation/swift/asyncstream)

The three feature stores use Swift Observation. The signed-in view creates the repository and its three stores once per session. Child views read the stores directly, so each child tracks the values it uses. A store tracks its repository as one dependency, so one write can refresh several values derived from it. The signed-in view still observes the repository's own loading and submission status. ClubFeedStore still supplies the Feed list and the post count in Me. [Apple's SwiftUI Observation session](https://developer.apple.com/videos/play/wwdc2023/10149/)

## Pending match photos

The configured repository keeps pending match photos in a versioned GRDB database, keyed by account and photo ID. The legacy JSON import records a receipt in the same transaction as the photos. It retains the old bytes and can retry an interrupted import while preserving the previous partial-recovery behavior. [Migration and recovery guide](MIGRATION.md)

## Standard appearance

The tab bar uses SwiftUI's `toolbarBackground` and `tint`, and navigation titles use the system style. The background uses the static `ClubBackdrop` asset. The Feed section selector uses SwiftUI buttons and the shared palette.

The app retains its startup `UISegmentedControl.appearance()` settings for native segmented pickers such as Public / Hidden in Me. SwiftUI's segmented picker style does not expose separate colors for the track and selected segment. The proxy sets both colors using the system's Reduce Transparency setting at launch. [UIKit segmented control appearance](https://developer.apple.com/documentation/uikit/uisegmentedcontrol)

## Tests

Run the `ProjectL` scheme's Test action on an iPhone simulator. `ProjectLTests` uses Swift Testing for camera targets, GIF decoding, multicast and subscriber cancellation, and updates to all three stores after one demo repository change. The suite also checks one set of stores per session and pending-photo migration, retry, and account cleanup. `ProjectLUITests` uses XCTest and Debug-only launch arguments to check the court map and a decoded GIF in a sample post. A separate UI test publishes in the normal demo and checks the new post in Feed and the post count in Me.

- [Design assets](DESIGN_ASSETS.md)
- [Maintenance map](MAINTENANCE_MAP.md)
- [Execution log](EXECUTION_LOG.md)
- [R1.2 simulator evidence](Evidence/R1.2/)
