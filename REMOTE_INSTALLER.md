# Remote Installer Setup Guide

## Overview

The `install-remote.sh` script enables one-line installation of send-to-slack directly from the repository, similar to Homebrew's installer pattern. This allows containers and CI/CD pipelines to install the latest version without rebuilding images when the repository changes.

## What Was Created

1. **`install-remote.sh`** - Standalone installer script that can be called via curl
2. **Updated `README.md`** - Added installation instructions for the remote installer

## How It Works

The installer script:
1. Checks prerequisites (bash 4.0+, curl, jq, git)
2. Clones the repository to a temporary directory
3. Runs the existing `install.sh` script
4. Cleans up temporary files
5. Fails gracefully if prerequisites are missing

## Usage

### Basic Installation (default: `/usr/local`)
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/install-remote.sh)"
```

### Custom Installation Prefix
```bash
INSTALL_PREFIX=/opt /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/install-remote.sh)"
```

### Install from Specific Branch
```bash
INSTALL_BRANCH=develop /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/install-remote.sh)"
```

## Requirements for This to Work

### 1. Repository Access
- The script assumes the repository is publicly accessible at `https://github.com/bluekornchips/send-to-slack.git`
- The `install-remote.sh` file must be accessible via raw.githubusercontent.com at:
  `https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/install-remote.sh`

### 2. Prerequisites Check
The installer checks for and requires:
- **Bash 4.0+** - For associative arrays and modern bash features
- **curl** - To download the installer script
- **jq** - Required by send-to-slack for JSON processing
- **git** - To clone the repository

If any prerequisites are missing, the installer will:
- Display clear error messages
- Provide installation links for missing dependencies
- Exit with a non-zero status code

### 3. Installation Behavior
- Default installation prefix: `/usr/local`
- If installing to a system directory (not under `$HOME`), sudo will be required
- The script automatically detects if sudo is needed
- Installation follows the same process as the local `install.sh` script

## Benefits

1. **No Image Rebuilds**: Containers can install the latest version without rebuilding
2. **Always Up-to-Date**: Pulls from the repository branch (default: `main`)
3. **Safe**: Fails if prerequisites are missing rather than installing broken software
4. **Flexible**: Supports custom installation prefixes and branch selection
5. **Clean**: Automatically cleans up temporary files

## Testing

To test the installer locally before pushing:

```bash
# Test syntax
bash -n install-remote.sh

# Test with a local file (simulating curl)
cat install-remote.sh | bash

# Test with custom prefix
INSTALL_PREFIX=/tmp/test-install bash install-remote.sh
```

## Container Usage Example

```dockerfile
FROM ubuntu:22.04

# Install prerequisites
RUN apt-get update && apt-get install -y \
    bash curl jq git \
    && rm -rf /var/lib/apt/lists/*

# Install send-to-slack
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/install-remote.sh)"

# Use send-to-slack
RUN echo '{"source": {...}, "params": {...}}' | send-to-slack
```

## Troubleshooting

### Issue: "Missing required dependencies"
**Solution**: Install the missing dependencies (curl, jq, git) before running the installer.

### Issue: "Failed to clone repository"
**Solution**: 
- Check network connectivity
- Verify the repository URL is correct
- Ensure git is installed and accessible

### Issue: "sudo is required but not available"
**Solution**: 
- Install to a location you have write access to: `INSTALL_PREFIX=$HOME/.local`
- Or install sudo in your container/environment

### Issue: "Installation failed"
**Solution**: 
- Check the error messages from the underlying `install.sh` script
- Verify you have write permissions to the installation prefix
- Ensure all repository files are present and valid

## Security Considerations

- The installer downloads and executes code from the internet
- Always verify the repository URL matches the expected source
- Consider pinning to a specific commit or tag for production use
- Review the installer script before use in sensitive environments

## Future Enhancements

Potential improvements:
1. Support for installing from a specific commit/tag
2. Checksum verification of downloaded files
3. Offline installation mode (using pre-downloaded tarball)
4. Support for installing from a local file path
5. Progress indicators for long-running operations
