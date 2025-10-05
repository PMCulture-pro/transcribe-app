# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Security Features

### 1. Model Integrity Verification
- All downloaded models are verified using SHA256 checksums
- Installation fails if checksum doesn't match
- Protects against corrupted or tampered models

### 2. Secure Installation Process
- Homebrew installation requires explicit user confirmation
- Installation script is downloaded to temporary file and can be inspected
- No automatic execution of remote scripts without user review

### 3. Local-Only Processing
- All transcription happens locally on your device
- No data is sent to external servers
- Your audio/video files never leave your computer

### 4. User Directory Installation
- Installs only in user directories (`~/Library/Application Support/`)
- Does not require root/sudo privileges
- No system-wide modifications

### 5. Safe File Handling
- All file paths properly quoted to prevent command injection
- Validation of input files before processing
- Temporary files cleaned up after use

## Reporting a Vulnerability

If you discover a security vulnerability in Transcribe App, please report it responsibly:

### How to Report

1. **DO NOT** open a public GitHub issue for security vulnerabilities
2. Send an email to: **sd.reg01@bk.ru**
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Any suggested fixes

### What to Expect

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 5 business days
- **Fix Timeline**: Depends on severity
  - Critical: 7 days
  - High: 14 days
  - Medium: 30 days
  - Low: Best effort

### Disclosure Policy

- We request that you do not publicly disclose the vulnerability until we've had a reasonable time to fix it
- We will credit you in the security advisory (if you wish)
- We will notify users of security updates through GitHub releases

## Known Limitations

### 1. Homebrew Trust
- The installer relies on Homebrew from brew.sh
- Users should verify they're downloading from the official Homebrew source

### 2. HuggingFace Dependencies
- AI model is downloaded from HuggingFace
- While we verify checksums, the source repository could be compromised
- We monitor the upstream repository for any suspicious changes

### 3. macOS Gatekeeper
- Application is not code-signed (requires Apple Developer account)
- Users may see security warnings from macOS
- Users should only download from official GitHub repository

## Security Best Practices for Users

### Before Installation

1. **Verify Source**: Only download from official GitHub repository
   ```
   https://github.com/PMCulture-pro/transcribe-app
   ```

2. **Check Release Signatures**: Verify you're using an official release

3. **Review Scripts**: Installation scripts are open source - review before running

### During Installation

1. **Inspect Homebrew Script**: Installer shows first 10 lines before execution
2. **Confirm Each Step**: Installation asks for confirmation at critical steps
3. **Monitor Progress**: Watch for any unexpected behavior

### After Installation

1. **Verify Checksum**: Installation confirms model integrity
2. **Check Permissions**: Application should only access:
   - Your selected audio/video files
   - Installation directory
   - Temporary files

3. **Monitor Activity**: No network activity should occur during transcription

## Update Policy

- Security updates will be released as soon as possible
- All security fixes will be clearly marked in release notes
- Users will be notified through GitHub release notifications

## Contact

For security concerns:
- Email: **sd.reg01@bk.ru**
- GitHub Security Advisories: https://github.com/PMCulture-pro/transcribe-app/security/advisories

For general questions:
- GitHub Issues: https://github.com/PMCulture-pro/transcribe-app/issues
- GitHub Discussions: https://github.com/PMCulture-pro/transcribe-app/discussions

---

**Last Updated**: 2025-10-05

Thank you for helping keep Transcribe App secure!

