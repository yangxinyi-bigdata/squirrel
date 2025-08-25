# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Squirrel is a macOS input method for Rime Input Method Engine (RIME). This is the GPT5/scroll branch which appears to be a fork with enhanced functionality including scroll support and markdown features. The project is built using Swift and integrates with the librime C++ engine.

## Build System

### Primary Build Commands

Build the project using make:
```bash
make                    # Build release version
make debug              # Build debug version
make package            # Build and create installer package
make install            # Install directly to system (requires sudo)
```

### Build Options

Set environment variables for different configurations:
```bash
# For universal binary (Apple Silicon + Intel)
make ARCHS='arm64 x86_64' BUILD_UNIVERSAL=1

# With code signing
make DEV_ID="Your Apple ID name"

# With specific deployment target
make MACOSX_DEPLOYMENT_TARGET='13.0'
```

### Dependencies Management

Handle dependencies:
```bash
make deps               # Build all dependencies
make clean              # Clean build artifacts
make clean-deps         # Clean dependency artifacts
make clean-package      # Clean package artifacts
```

### Shortcut Installation

Use the action script to quickly get librime binaries:
```bash
bash ./action-install.sh
```

## Architecture

### Core Components

1. **SquirrelInputController** (`sources/SquirrelInputController.swift`)
   - Main input method controller implementing IMKInputController
   - Handles keyboard events, text composition, and Rime session management
   - Integrates with the librime engine via C API

2. **SquirrelPanel** (`sources/SquirrelPanel.swift`) 
   - UI coordination center managing the candidate window display
   - Handles window positioning, user interactions (mouse, scroll)
   - Coordinates between input controller and view rendering

3. **SquirrelView** (`sources/SquirrelView.swift`)
   - Custom NSView for rendering candidate text and UI elements
   - Handles visual presentation and user interaction events

4. **SquirrelTheme** (`sources/SquirrelTheme.swift`)
   - Theme and styling system for the UI appearance
   - Manages colors, fonts, layout parameters

5. **SquirrelConfig** (`sources/SquirrelConfig.swift`)
   - Configuration management for user settings

### Key Features

- **Input Method Integration**: Full macOS InputMethodKit integration
- **Rime Engine**: Powered by librime with C API bindings
- **Multi-layout Support**: Vertical/horizontal candidate layouts  
- **Smart Positioning**: Intelligent window placement avoiding screen edges
- **Mouse Interaction**: Click selection, hover highlighting, scroll paging
- **Theme System**: Customizable appearance with transparency support
- **Plugin Support**: Extensible with Rime plugins (lua, octagram, predict)

### Dependencies

- **librime**: Core input method engine (C++)
- **Rime plugins**: librime-lua, librime-octagram, librime-predict
- **Sparkle**: Auto-update framework
- **Plum**: Package manager for Rime schemas and dictionaries
- **OpenCC**: Chinese text conversion library

## Development Workflow

### Prerequisites

- Xcode 14.0 or later
- cmake
- macOS 13.0+ for deployment target

### Building from Source

1. Clone with submodules:
   ```bash
   git clone --recursive https://github.com/rime/squirrel.git
   ```

2. Install plugins (optional):
   ```bash
   bash librime/install-plugins.sh rime/librime-lua rime/librime-octagram
   ```

3. Set up Boost (choose one option):
   ```bash
   # Option A: Build from source
   export BUILD_UNIVERSAL=1
   bash librime/install-boost.sh
   export BOOST_ROOT="$(pwd)/librime/deps/boost-1.84.0"
   
   # Option B: Use Homebrew
   brew install boost
   ```

4. Build:
   ```bash
   make
   ```

### Testing and Verification

- Test installation by installing to system: `make install`
- Check for proper integration with macOS input method system
- Verify candidate window display and interaction
- Test with various applications and input scenarios

## File Structure

- `sources/`: Swift source files for the input method
- `librime/`: Rime engine submodule  
- `Sparkle/`: Auto-update framework submodule
- `plum/`: Schema and dictionary package manager
- `resources/`: App resources, Info.plist, entitlements
- `package/`: Packaging and signing scripts
- `data/`: Runtime data files (schemas, dictionaries)
- `Makefile`: Main build configuration
- `Squirrel.xcodeproj/`: Xcode project file

## Common Tasks

- **Add new input schema**: Use plum package manager or modify `data/plum/` 
- **Customize UI theme**: Modify SquirrelTheme.swift and related resources
- **Debug input handling**: Focus on SquirrelInputController event processing
- **UI layout changes**: Work with SquirrelPanel and SquirrelView coordination
- **Build configuration**: Modify Makefile or environment variables