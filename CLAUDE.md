# SparkleShare-iOS

iOS client for the SparkleShare file-sharing platform.

## Quick Reference

- **Language**: Objective-C with Swift (SwiftUI for markdown rendering)
- **Architecture**: MVC with delegate-based communication
- **Min iOS**: 16.0
- **Bundle ID**: com.sb.SparkleShare
- **Device Support**: Universal (iPhone + iPad)

## Project Structure

```
SparkleShare/
├── Classes/           # 46 Objective-C source files
├── Supporting/        # main.m entry point
└── Resources/
    ├── xibs/          # 14 XIB files (iPhone/iPad variants)
    ├── Localization/  # en, de
    └── Graphics/      # App icons
libs/                  # Git submodules (AFNetworking, SVProgressHUD, UIImage-FileType)
Pods/                  # CocoaPods dependencies
```

## Key Dependencies

| Library | Purpose |
|---------|---------|
| AFNetworking | HTTP networking |
| SVProgressHUD | Loading indicators |
| AVFoundation | QR code scanning |
| cmark-gfm | GitHub Flavored Markdown parsing (C library) |
| SwiftUI | Markdown rendering |
| QuickLook | File previews |

## Core Components

### Models
- `SSConnection` - Server connection, authentication, HTTP requests
- `SSRootFolder` / `SSFolder` / `SSFile` - File system hierarchy
- `SSFolderItem` - Base class for files/folders
- `SSRecentFile` - Data model for recently opened file metadata
- `SSRecentFilesManager` - Singleton manager for recent files persistence (stored in NSUserDefaults)

### View Controllers
- `StartingViewController` - Initial login screen
- `QRCodeLoginInputViewController` - QR code scanning
- `ManualLoginInputViewController` - Manual URL entry
- `FolderViewController` - Folder contents display
- `FileViewController` - QuickLook file preview
- `FileEditController` - Text editor with SwiftUI markdown preview
- `SettingsViewController` - App settings (device name, self-signed certs, logout)

### Markdown Rendering (Swift)
- `MarkdownParser` - Parses markdown to AST using cmark-gfm C library
- `MarkdownView` - SwiftUI view that renders the markdown AST
- `MarkdownHostingView` - UIKit wrapper for embedding SwiftUI in Objective-C

## API Authentication

Custom headers for SparkleShare server:
- `X-SPARKLE-IDENT` - Device identifier
- `X-SPARKLE-AUTH` - Authentication token

Credentials and recent files are stored in NSUserDefaults.

## Build Notes

- Uses CocoaPods + Git submodules for dependencies
- Separate XIB files for iPhone (`*_iPhone.xib`) and iPad (`*_iPad.xib`)
- Some legacy files compiled with `-fno-objc-arc`

## Features

- Hierarchical folder navigation with git revision tracking
- Pull-to-refresh for content reloading
- QuickLook preview for 100+ file types
- SwiftUI markdown preview
- Text file editing
- QR code-based device linking
- Recent files list for easy access (last 20 accessed files)

## Development notes
- Don't build the project (save tokens), you can ask if you need to check if everything builds
  correctly
