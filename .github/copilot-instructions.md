# Copilot Instructions for AdminLogging SourcePawn Plugin

## Repository Overview

This repository contains the **AdminLogging** SourcePawn plugin for SourceMod, which logs admin actions to Discord via webhooks. The plugin captures admin command executions and sends formatted messages to Discord channels or threads, with optional integration for demo recording information.

**Plugin Version**: 1.3.8  
**Primary File**: `addons/sourcemod/scripting/AdminLogging.sp`

## Technical Environment

- **Language**: SourcePawn
- **Platform**: SourceMod 1.11+ (minimum), 1.12+ recommended
- **Build System**: SourceKnight 0.2
- **Compiler**: SourcePawn compiler via SourceKnight
- **CI/CD**: GitHub Actions with automated builds and releases

## Dependencies

The plugin has the following dependencies managed via `sourceknight.yaml`:

1. **sourcemod** (1.11.0-git6934): Core SourceMod framework
2. **discordwebapi**: Required for Discord webhook functionality
3. **AutoRecorder** (optional): Provides demo recording information in logs
4. **Extended-Discord** (optional): Enhanced Discord logging for error messages

### Dependency Management
- Dependencies are automatically downloaded and configured by SourceKnight
- Optional dependencies use `#tryinclude` and library existence checks
- Plugin gracefully handles missing optional dependencies

## Build System

### SourceKnight Configuration
The project uses SourceKnight build system configured in `sourceknight.yaml`:

```yaml
# Key configuration elements:
- Root: /
- Output: /addons/sourcemod/plugins  
- Target: AdminLogging
```

### Build Commands
```bash
# Build using SourceKnight (via GitHub Actions)
# Local development requires SourceKnight installation
```

### CI/CD Pipeline
- **Trigger**: Push, PR, or manual dispatch
- **Platform**: Ubuntu 24.04
- **Process**: Build → Package → Release
- **Artifacts**: Compiled `.smx` files and dependencies
- **Releases**: Automatic tagging and release creation

## Code Standards & Style

### SourcePawn-Specific Standards
- **Pragmas**: Always use `#pragma newdecls required` (line 1)
- **Includes**: Use `#include <sourcemod>` and `#include <sdktools>`
- **Variables**: Prefix globals with `g_` (e.g., `g_cvWebhook`, `g_sMap`)
- **Functions**: Use PascalCase for public functions
- **Constants**: Use UPPERCASE with underscores (e.g., `MAX_RAMDOM_INT`)

### Plugin-Specific Patterns
- **ConVars**: Create protected ConVars for sensitive data (webhooks)
- **Error Handling**: Use LogError for critical failures, with ExtendedDiscord fallback
- **Memory Management**: Always use `delete` for cleanup, never `.Clear()` on StringMaps/ArrayLists
- **String Escaping**: Escape Discord markdown characters in messages
- **Async Operations**: All webhook calls are asynchronous with retry logic

## Plugin Architecture

### Core Components

1. **ConVar Management**
   - `sm_adminlogging_webhook`: Discord webhook URL (protected)
   - `sm_adminlogging_webhook_retry`: Retry count for failed webhooks
   - `sm_adminlogging_avatar`: Bot avatar URL
   - `sm_adminlogging_username`: Bot display name
   - `sm_adminlogging_channel_type`: Channel type (0=text, 1=thread)
   - `sm_adminlogging_threadid`: Thread ID for thread replies

2. **Event Handling**
   - `OnLogAction`: Intercepts admin actions and formats for Discord
   - Library detection for optional plugins (AutoRecorder, ExtendedDiscord)
   - Map change tracking for context information

3. **Webhook System**
   - Asynchronous webhook sending with retry logic
   - Support for both text channels and thread replies
   - Message formatting with Discord markdown escaping
   - Error handling with fallback to ExtendedDiscord if available

### Key Functions

- `SendWebHook()`: Primary webhook sending function with retry logic
- `OnWebHookExecuted()`: Callback handling webhook responses and retries
- `Timer_ResendWebhook()`: Timer-based retry mechanism

## Development Guidelines

### When Adding Features
1. **ConVars**: Add new configuration options as ConVars with descriptive names
2. **Optional Dependencies**: Use `#tryinclude` and library existence checks
3. **Error Handling**: Provide meaningful error messages and fallback behavior
4. **Memory Management**: Always clean up DataPacks and other allocated resources
5. **Async Operations**: Keep all external API calls (webhooks) asynchronous

### Message Formatting
- Escape Discord markdown: ` * ~ | > / @ "`
- Include context: map name, team scores, timestamp
- Add demo information when AutoRecorder is available
- Keep messages under Discord's character limits

### Testing Considerations
- Test with and without optional dependencies
- Verify webhook retry logic with network failures
- Test both text channel and thread functionality
- Validate message formatting and escaping

## File Structure

```
/
├── .github/
│   ├── workflows/ci.yml          # CI/CD pipeline
│   └── copilot-instructions.md   # This file
├── addons/sourcemod/scripting/
│   └── AdminLogging.sp           # Main plugin source
├── sourceknight.yaml             # Build configuration
└── .gitignore                    # Git ignore rules
```

## Common Patterns

### Library Detection Pattern
```sourcepawn
public void OnAllPluginsLoaded()
{
    g_Plugin_AutoRecorder = LibraryExists("AutoRecorder");
}

public void OnLibraryAdded(const char[] sName)
{
    if (strcmp(sName, "AutoRecorder", false) == 0)
        g_Plugin_AutoRecorder = true;
}
```

### Async Webhook Pattern
```sourcepawn
// 1. Create webhook object
Webhook webhook = new Webhook(message);

// 2. Set properties
webhook.SetUsername(name);
webhook.SetAvatarURL(avatar);

// 3. Execute asynchronously
webhook.Execute(url, callback, datapack);

// 4. Clean up immediately
delete webhook;
```

### Error Handling Pattern
```sourcepawn
if (!webhook_success) {
    if (!g_Plugin_ExtDiscord) {
        LogError("[%s] Error message", PLUGIN_NAME);
    }
    #if defined _extendeddiscord_included
    else {
        ExtendedDiscord_LogError("[%s] Error message", PLUGIN_NAME);
    }
    #endif
}
```

## Security Considerations

- **Webhook URLs**: Always mark webhook ConVars as `FCVAR_PROTECTED`
- **Message Sanitization**: Escape all user input to prevent Discord exploits
- **Input Validation**: Validate all configuration values before use
- **Error Messages**: Don't expose sensitive information in error logs

## Performance Notes

- **Async Operations**: All webhook calls are non-blocking
- **Memory Management**: Immediate cleanup of webhook objects and DataPacks
- **String Operations**: Minimal string manipulation in hot paths
- **Timer Usage**: Controlled retry logic with exponential backoff

## Troubleshooting

### Common Issues
1. **Missing Dependencies**: Check SourceKnight dependency resolution
2. **Webhook Failures**: Verify URL format and Discord permissions
3. **Thread Replies**: Ensure thread ID is valid and accessible
4. **Build Failures**: Check SourceKnight version and dependency availability

### Debugging
- Enable debug logging for webhook responses
- Use ExtendedDiscord for enhanced error reporting
- Check ConVar values with `sm_cvar` commands
- Monitor server console for error messages

## Release Process

1. **Version Updates**: Update version in plugin info
2. **Testing**: Verify functionality on development server
3. **Commit**: Push changes trigger CI/CD pipeline
4. **Automated**: GitHub Actions handles build, package, and release
5. **Tagging**: Use semantic versioning for releases

This plugin follows SourceMod best practices and provides robust Discord integration for admin action logging.