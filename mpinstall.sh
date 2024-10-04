#!/bin/bash
#
# MicroPython Package Installer
# Created by: Ubi de Feo and Sebastian Romero
# 
# Installs MicroPython Packages to the /lib folder of a board using mpremote.
# 
# - Installation is recursive, so all files and folders in the package directory.
# - Supports multiple packages and optional arguments.
# - Accepts optional argument to compile .py files to .mpy. [--mpy]
# - Accepts optional argument to skip resetting the board. [--no-reset]
#
# ./install.sh <PACKAGE_FOLDER> ... <PACKAGE_FOLDER> [--mpy][--no-reset]

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

# Check if device is present/connectable
# returns 0 if device is present, 1 if it is not
function device_present {
  # Run mpremote and capture the error message
  echo "Checking if a MicroPython board is available..."
  sys_info="${PYTHON_HELPERS}sys_info()"
  error=$(mpremote exec "$sys_info")
  # Return error if error message contains "OSError: [Errno 2] ENOENT"
  if [[ $error == *"no device found"* ]]; then
      return 0
  else
      return 1
  fi
}


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

function create_folder {
  echo "Creating $1 on board"
  error=$(mpremote mkdir "$1")
  # Print error message if return code is not 0
  if [ $? -ne 0 ]; then
    echo "Error: $error"
  fi
}

function delete_folder {
  echo "Deleting $1 on board"
  delete_folder="${PYTHON_HELPERS}delete_folder(\"/$1\")"
  mpremote exec "$delete_folder"
}


function install_package {
  # Name to display during installation
  # PKGNAME="Generic package for MicroPython"
  PKGNAME=`basename $1`
  # Destination directory for the package on the board
  PKGDIR=`basename $1`
  # Source directory for the package on the host
  SRCDIR=`realpath $1`
  # Board's library directory
  LIBDIR="/lib"

  # echo "Package name: $PKGNAME"
  # echo "Package directory: $PKGDIR"
  # echo "Source directory: $SRCDIR"
  # echo "Library directory: $LIBDIR"
  # echo "Installing $PKGNAME"

  if directory_exists "${LIBDIR}/${PKGDIR}"; then
    echo "Deleting $LIBDIR/$PKGDIR on board"
    delete_folder="${PYTHON_HELPERS}delete_folder(\"${LIBDIR}/${PKGDIR}\")"
    mpremote exec "$delete_folder"
  fi
  
  package_files=($(find $1))
  items_count=${#package_files[@]}
  current_item=0
  for item_path in "${package_files[@]}"; do
    

    item=`basename $item_path`
    if [ ! -f "$item_path" ] && [ ! -d "$item_path" ]; then
      echo -n "symlink file ignored"
      continue
    else
      current_item=$((current_item+1))
      echo -n "[$(printf "%2d" $current_item)/$(printf "%2d" $items_count)] "
      if [ -d "$item_path" ]; then
        
        create_folder "$LIBDIR/$item_path"
      elif [ -f "$item_path" ]; then
        f_name=`basename $item`
        source_extension="${f_name##*.}"
        destination_extension=$source_extension
        if [[ "$ext" == "mpy" && "$source_extension" == "py" ]]; then
          echo "Compiling $f_name to ${f_name%.*}.$ext"
          mpy-cross "$item_path"
          destination_extension=$ext
          copy_file ${item_path%.*}.$destination_extension :$LIBDIR/${item_path%.*}.$destination_extension
        else
          copy_file $item_path :$LIBDIR/$item_path
        fi
      fi
    fi

    
      

  done

  if [ "$ext" == "mpy" ]; then
    echo "cleaning up mpy files"
    rm $SRCDIR/*.mpy
  fi

  echo -e "\n***Package $PKGNAME installed successfully***\n"
}

# No arguments passed
if [[ $1 == "" ]]; then
  echo "Usage: $0 <package_directory> [--mpy][--no-reset]"
  exit 1
fi

# Check if mpremote is installed
if ! command -v mpremote &> /dev/null
then
    echo "mpremote could not be found. Please install it by running:"
    echo "pip install mpremote"
    exit 1
fi

reset=true
ext="py"
packages=()
for arg in "$@"; do
  if [ "$arg" == "--no-reset" ]; then
    reset=false
    continue
  fi
  if [ "$arg" == "--mpy" ]; then
    ext="mpy"
    continue
  fi
  packages+=($arg)
done


# Start the installation process
echo "MicroPython Package Installer"
echo "-----------------------------"
echo "Packages:" 
for package in "${packages[@]}"; do
  echo "• $package"
done

if device_present == 0; then
  echo "No device found. Please connect a MicroPython board and try again."
  exit 1
fi

package_number=0
start_dir=`pwd`
for package in "${packages[@]}"; do
  package_number=$((package_number+1))
  echo "Installing `basename $package` ($package_number/${#packages[@]})"
  parent_dir=`realpath ${package%/*}`
  find $parent_dir -name ".DS_Store" -type f -delete
  cd $parent_dir
  install_package `basename $package`
  cd $start_dir
done

if [ "$reset" = true ]; then
  echo "Resetting target board ..."
  mpremote reset
  exit 1
fi
