# UsualUI: practical source map

## Implemented today

- `Package.swift` — product/resource declarations
- `Sources/UsualUI/RootView.swift` — root composition
- `Sources/UsualUI/Theme/Theme.swift` — colors and RGB parser
- `Sources/UsualUI/Thread/Composer.swift` — message input
- `Sources/UsualUI/Thread/ApprovalCard.swift` — approval UI
- `Sources/UsualUI/Thread/SecretCard.swift` — masked secret and sudo prompts
- `Sources/UsualUI/Room/RoomPane.swift` — rooms

No local database schema/migration files were found in this layer; that does not imply dependencies or remote systems lack persistence.

Build output, dependencies and caches are not source owners. Do not introduce assumed API, jobs, migrations or shared-package folders merely because another product has them. Put new behavior next to the relevant source owner above; update the map when introducing a necessary new boundary.
