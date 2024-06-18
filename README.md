# mpy_utils

Useful tools for MicroPython development

## `mpinstall.sh`

Shell script (Mac OS, Linux, [PowerShell?]) to install a package in development to the board's `/lib` folder.
Its ideal place is in your OS's `$PATH` so that it can be invoked from anywhere.

Requirements: mpremote


Running simply `./mpinstall.sh` will check for `mpremote` and display usage:

Usage:

```shell
./mpinstall.sh <package_directory> [mpy]
```

Options:
`mpy` as an extra argument will `mpy-cross` all the files before copying and remove them after upload is successful.

### Example
Assuming we are working on the Arduino Runtime for MicroPython, if we are in the current directory tree

```shell
.
├── LICENSE
├── README.md
├── arduino
│   ├── __init__.py
│   ├── arduino.py
│   ├── examples
│   │   ├── 00_basic.py
│   │   ├── 01_arduino_blink.py
│   │   └── 02_nano_esp32_advanced.py
│   └── template.tpl
├── install.sh
└── package.json
```

To install the package the following command would need to be issued, assuming `mpinstall.sh` is in your OS's `$PATH`

```shell
mpinstall.sh arduino
```

The script will take care of everything, delete the folder if present on the board, create the folder and upload its content.