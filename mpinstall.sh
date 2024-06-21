#!/bin/bash
#
# MicroPython Package Installer
# Created by: Ubi de Feo and Sebastian Romero
# 
# Installs a MicroPython Package to a board using mpremote.
# 
# This script accepts an optional argument to compile .py files to .mpy.
# Simply run the script with the optional argument:
#
# ./install.sh mpy

PYTHON_HELPERS='''
import os

os.chdir("/")

def is_directory(path):
  return True if os.stat(path)[0] == 0x4000 else False

def get_all_files(path, array_of_files = []):
    files = os.ilistdir(path)
    for file in files:
        is_folder = file[1] == 16384
        p = path + "/" + file[0]
        array_of_files.append({
            "path": p,
            "type": "folder" if is_folder else "file"
        })
        if is_folder:
            array_of_files = get_all_files(p, array_of_files)
    return array_of_files

def delete_folder(path):
    files = get_all_files(path)
    for file in files:
        if file["type"] == "file":
            os.remove(file["path"])
    for file in reversed(files):
        if file["type"] == "folder":
            os.rmdir(file["path"])
    os.rmdir(path)

def sys_info():
    import sys
    print(sys.platform, sys.implementation.version)
    
'''

# Check if mpremote is installed
if ! command -v mpremote &> /dev/null
then
    echo "mpremote could not be found. Please install it by running:"
    echo "pip install mpremote"
    exit 1
fi


if [[ $1 == "" ]]; then
  echo "Usage: $0 <package_directory> [mpy]"
  exit 1
fi


# Name to display during installation
# PKGNAME="Generic package for MicroPython"
PKGNAME=`basename $1`
# Destination directory for the package on the board
PKGDIR=`basename $1`
# Source directory for the package on the host
SRCDIR=`realpath $1`
# Board library directory
LIBDIR="lib"


# Check if device is present/connectable
# returns 0 if device is present, 1 if it is not
function device_present {
  # Run mpremote and capture the error message
  echo "device present?"
  sys_info="${PYTHON_HELPERS}sys_info()"
  error=$(mpremote exec "$sys_info")
  echo $error
  # Return error if error message contains "OSError: [Errno 2] ENOENT"
  if [[ $error == *"no device found"* ]]; then
      return 0
  else
      return 1
  fi
}


if device_present == 0; then
  echo "No device found. Please connect a device and try again."
  exit 1
fi

# Check if a directory exists
# Returns 0 if directory exists, 1 if it does not
function directory_exists {
  # Run mpremote and capture the error message
  error=$(mpremote fs ls $1)

  # Return error if error message contains "OSError: [Errno 2] ENOENT"
  if [[ $error == *"OSError: [Errno 2] ENOENT"* ]]; then
      return 1
  else
      return 0
  fi
}

# Copies a file to the board using mpremote
# Only produces output if an error occurs
function copy_file {
  echo "Copying $1 to $2"
  # Run mpremote and capture the error message
  error=$(mpremote cp $1 $2)

  # Print error message if return code is not 0
  if [ $? -ne 0 ]; then
    echo "Error: $error"
  fi
}

# Deletes a file from the board using mpremote
# Only produces output if an error occurs
function delete_file {
  echo "Deleting $1"
  # Run mpremote and capture the error message
  error=$(mpremote rm $1)

  # Print error message if return code is not 0
  if [ $? -ne 0 ]; then
    echo "Error: $error"
  fi
}

echo "Installing $PKGNAME"

# If directories do not exist, create them
if ! directory_exists "/${LIBDIR}"; then
  echo "Creating $LIBDIR on board"
  mpremote mkdir "${LIBDIR}"
fi

if directory_exists "/${LIBDIR}/${PKGDIR}"; then
  echo "Deleting $LIBDIR/$PKGDIR on board"
  delete_folder="${PYTHON_HELPERS}delete_folder(\"/${LIBDIR}/${PKGDIR}\")"
  mpremote exec "$delete_folder"
  # mpremote mkdir "/${LIBDIR}/${PKGDIR}"
fi
mpremote mkdir "/${LIBDIR}/${PKGDIR}"

ext="py"
if [ "$2" = "mpy" ]; then
  ext=$2
  echo ".py files will be compiled to .mpy"
fi

existing_files=$(mpremote fs ls ":/${LIBDIR}/${PKGDIR}")

for filename in $SRCDIR/*; do
    f_name=`basename $filename`
    source_extension="${f_name##*.}"
    destination_extension=$source_extension

    # If examples are distributed within the package
    # ensures they are copied but not compiled to .mpy
    if [[ -d $filename && "$f_name" == "examples" ]]; then
      if ! directory_exists "/${LIBDIR}/${PKGDIR}/examples"; then
        echo "Creating $LIBDIR/$PKGDIR/examples on board"
        mpremote mkdir "/${LIBDIR}/${PKGDIR}/examples"
      fi

      for example_file in $filename/*; do
        example_f_name=`basename $example_file`
        example_source_extension="${example_f_name##*.}"
        example_destination_extension=$example_source_extension

        if [[ $existing_files == *"${example_f_name%.*}.$example_source_extension"* ]]; then
          delete_file ":/${LIBDIR}/$PKGDIR/examples/${example_f_name%.*}.$example_source_extension"
        fi

        if [ "$example_source_extension" = "py" ] && [[ $existing_files == *"${example_f_name%.*}.mpy"* ]]; then
          delete_file ":/${LIBDIR}/$PKGDIR/examples/${example_f_name%.*}.mpy"
        fi

        copy_file $filename/${example_f_name%.*}.$example_destination_extension ":/${LIBDIR}/$PKGDIR/examples/${example_f_name%.*}.$example_destination_extension"
      done
      continue
    fi

    if [[ "$ext" == "mpy" && "$source_extension" == "py" ]]; then
      echo "Compiling $SRCDIR/$f_name to $SRCDIR/${f_name%.*}.$ext"
      mpy-cross "$SRCDIR/$f_name"
      destination_extension=$ext
    fi
    
    # Make sure previous versions of the given file are deleted.
    if [[ $existing_files == *"${f_name%.*}.$source_extension"* ]]; then
      delete_file ":/${LIBDIR}/$PKGDIR/${f_name%.*}.$source_extension"
    fi

    # Check if source file has a .py extension and if a .mpy file exists on the board
    if [ "$source_extension" = "py" ] && [[ $existing_files == *"${f_name%.*}.mpy"* ]]; then
      delete_file ":/${LIBDIR}/$PKGDIR/${f_name%.*}.mpy"
    fi

    # Copy either the .py or .mpy file to the board depending on the chosen option
    copy_file $SRCDIR/${f_name%.*}.$destination_extension ":/${LIBDIR}/$PKGDIR/${f_name%.*}.$destination_extension"
done

if [ "$ext" == "mpy" ]; then
  echo "cleaning up mpy files"
  rm $SRCDIR/*.mpy
fi

echo "Done. Resetting target board ..."
mpremote reset