# Rally Club design assets

The six PNGs use the GPT artwork in [DesignSource/GPT-R2](DesignSource/GPT-R2). They were resized proportionally and center-cropped to the dimensions below. Keep these asset names when replacing artwork in Xcode.

| Asset | Size or format | Use |
| --- | --- | --- |
| `RallyClubIcon` | 1024 × 1024 px, opaque PNG | App icon |
| `RallyAvatar` | 256 × 256 px, PNG | Default member avatar and sample feed image |
| `CourtPreview` | 1200 × 640 px, PNG | Court finder introduction |
| `ClubBackdrop` | 672 × 1216 px, PNG | Static background |
| `TrainingLoungePlaceholder` | 960 × 640 px, PNG | Training lounge preview |
| `RallyLaunchBall` | 720 × 720 px, transparent PNG | Launch overlay illustration |
| `RallyLaunchBackground` | Universal sRGB color, `#F4F7F2` | Native launch screen and overlay background |
| `RallyAccent` | Universal sRGB color, `#48685F` | App accent |
| `rallyBallMotion` | Metal layer effect, scales with view | Moves the launch illustration before the existing fade |

The four tabs use SF Symbols at the system tab bar size.

| Tab | SF Symbol |
| --- | --- |
| Courts | `tennis.racket` |
| Feed | `bubble.left.and.bubble.right` |
| Training lounge | `figure.cooldown` |
| Me | `person.crop.circle` |

The demo court map is drawn in SwiftUI in `ProjectL/Components/CourtMapView.swift` and scales to the map container. Tab icons are defined in `ProjectL/Components/AppPalette.swift`.
