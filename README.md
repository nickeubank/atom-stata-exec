# stata-exec

Instruct Stata to execute currently open do-file on Mac OS X.

## Installation

`apm install stata-exec`

or

Search for `stata-exec` within package search in the Settings View.

## Configuration

### Keybindings

While `cmd-;` is bound to sending code in the package. If this conflicts with other
key-maps already in place,you must add the following binding in `~/.atom/keymap.cson`:

```javascript
'atom-workspace atom-text-editor:not([mini])':
  'cmd-;': 'stata-exec:run-dofile'
```

### Behavior

The "whichApp" configuration variable (which can be set in Settings) is the name of the version of Stata you are using. By default, it will just look for "Stata", but in some cases you may need to change that name (for example, to StataMP).

## Usage


## Notes

This is a hobby project based off a hobby project (`r-exec`).  It is currently Mac-only because these things are easy to do with AppleScript.  Any help on the Windows or Linux side would be great, as would addition of ability to run selections.


## TODO
- Support for Windows and Linux.
- Run selections
