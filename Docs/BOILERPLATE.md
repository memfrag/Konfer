## Boilerplate macOS App — Guide for LLM Customization

### What the boilerplate provides

This is a macOS SwiftUI app template with a `NavigationSplitView` sidebar, multiple window scenes, and infrastructure for settings, auth, engineering mode, and more. It uses several Apparata Swift packages.

### Structure

```
Snoopy/
├── macOS/
│   ├── MacApp.swift                    ← @main entry, registers all scenes
│   ├── MacAppDelegate.swift
│   ├── Main Window/
│   │   └── MainWindow.swift            ← WindowGroup containing Sidebar
│   ├── Sidebar/
│   │   ├── Sidebar.swift               ← NavigationSplitView with List + detail
│   │   ├── SidebarPane.swift           ← Enum of available panes (REPLACE)
│   │   └── SidebarFooter.swift
│   ├── Panes/                          ← Example panes (REPLACE)
│   │   ├── HelloWorldPane.swift        ← DELETE
│   │   ├── WhatsUpPane.swift           ← DELETE
│   │   ├── MoreStuffPane.swift         ← DELETE
│   │   ├── EmptyPane.swift             ← Keep/modify (no-selection state)
│   │   └── Pane Helper/
│   │       ├── Pane.swift              ← Generic pane wrapper
│   │       └── PaneBackground.swift
│   ├── Inspector/
│   │   └── InspectorPanel.swift        ← Example inspector (REMOVE if unused)
│   ├── Settings/
│   │   ├── SettingsWindow.swift
│   │   └── GeneralSettingsTab.swift
│   ├── Help Window/
│   │   ├── HelpWindow.swift            ← Shows "No help available"
│   │   └── HelpCommands.swift
│   ├── Menu Bar Button/
│   │   ├── MenuBarWindow.swift         ← REMOVE if unused
│   │   └── MenuBarPopup.swift
│   ├── Export/
│   │   ├── ExportCommands.swift        ← Example TSV export (REMOVE if unused)
│   │   └── MyExportDocument.swift
│   ├── My Menu Commands/
│   │   └── MyCommands.swift            ← Example "Build"/"Do Stuff" (REMOVE or replace)
│   ├── App Environment/
│   │   ├── AppEnvironment.swift        ← Dependency container
│   │   ├── AppEnvironment+Default.swift
│   │   ├── AppEnvironment+Live.swift
│   │   ├── AppEnvironment+Mock.swift
│   │   └── View+AppEnvironment.swift
│   └── Utilities/
│       └── NSWindow+AlwaysOnTop.swift  ← REMOVE if unused
│
├── All Platforms/
│   ├── Infrastructure/
│   │   ├── Auth/                       ← Mock auth service (REMOVE if unused)
│   │   ├── Engineering Mode/           ← Debug mode toggle (REMOVE if unused)
│   │   └── Settings/
│   │       ├── AppSettings.swift       ← Observable settings with KeyValueStore
│   │       ├── AppSettings+DefaultStore.swift
│   │       └── AppSettings+Mock.swift
│   ├── App Information/
│   │   ├── AppVersion.swift
│   │   └── OpenSourceAttributions.swift
│   └── Utilities/
│       ├── AppColorScheme.swift
│       ├── Color+InversePrimary.swift
│       └── EdgeInsets+Convenience.swift
│
└── Packages/
    └── AppDesign/                      ← Local design system package
```

### Adding/Deleting Files

The Xcode project uses PBXFileSystemSynchronizedRootGroup (folder references), so adding/deleting files Just Works.

### What to replace when building a new app

1. **Delete the example panes**: `HelloWorldPane.swift`, `WhatsUpPane.swift`, `MoreStuffPane.swift`
2. **Replace `SidebarPane.swift`**: The enum defines sidebar navigation items — replace with your app's navigation model
3. **Rewrite `Sidebar.swift`**: Replace the hardcoded `NavigationLink` list and detail `switch` with your content
4. **Update `MainWindow.swift`**: Remove commands you don't need (`ExportCommands`, `AlwaysOnTopCommand`, `MyCommands`)
5. **Update `MacApp.swift`**: Remove scenes you don't need (`MenuBarWindow`, `HelpWindow`, etc.)

### What to keep

- **AppEnvironment** — Dependency injection pattern, useful as-is
- **AppSettings** — Observable settings with persistence, just add your own keys
- **Pane.swift / PaneBackground.swift** — Generic pane wrapper, useful for consistent styling
- **EmptyPane.swift** — Good default for no-selection state
- **SettingsWindow** — Add your own tabs

### What to remove if unused

- `Inspector/` — Example inspector panel
- `Menu Bar Button/` — Menu bar extra window
- `Export/` — Example TSV file export
- `My Menu Commands/` — Example custom menu items
- `Auth/` — Mock authentication service
- `Engineering Mode/` — Debug mode infrastructure
- `NSWindow+AlwaysOnTop.swift` — Window always-on-top toggle

### Navigation pattern

The boilerplate uses an enum-based `NavigationSplitView`:
1. `SidebarPane` enum lists available panes
2. `Sidebar` has `@State var selection: SidebarPane?`
3. `NavigationLink(value:)` in the list drives selection
4. `switch selection` in the detail view renders the active pane

Replace this with whatever navigation model fits your app (list of data items, tree structure, etc.).
