# com.googlecode.iterm2.plist

Location of the file on MacOS:
~/Library/Preferences

This file is the iterm2 settings file, but in an xml converted state.

## Usage
The file, in binary form is used to get the iterm2 profile preferences.
I've created this from my own iterm2 settings and is using this file for being able to automatically setup iterm2 in new environments.

## Conversion

### To xml
plutil -convert xml1 com.googlecode.iterm2.plist

### To binary
plutil -convert binary1 com.googlecode.iterm2.plist
