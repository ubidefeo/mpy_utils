# mpy_utils

Useful tools for MicroPython development

## `mpinstall.sh`

Shell script (Mac OS, Linux, [PowerShell?]) to install a package in development to the board's `/lib` folder.

Requirements: mpremote

Running simply `mpinstall.sh` will check for `mpremote` and display usage:

Usage:

```shell
/opts/bin/mpinstall.sh <package_directory> [mpy]
```

Options:
`mpy` as an extra argument will `mpy-cross` all the files before copying and remove them after upload is successful.
