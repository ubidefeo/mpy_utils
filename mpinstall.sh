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
import sys

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
    
def get_root(has_flash_mount = True):
    if "/flash" in sys.path:
        return "/flash"
    else:
        return ""

os.chdir(get_root())
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
  output="Copying $1 to $2"
  echo -n "$output"
  # Run mpremote and capture the error message
  error=$(mpremote cp $1 $2)
  # Print error message if return code is not 0
  if [ $? -ne 0 ]; then
    echo "Error: $error"
  fi
  echo -ne "\r\033[2K"
  echo -e "\r√ $output"
}

# Deletes a file from the board using mpremote
# Only produces output if an error occurs
function delete_file {
  output="Deleting $1"
  echo -n "$output"
  # Run mpremote and capture the error message
  error=$(mpremote rm $1)
  # Print error message if return code is not 0
  if [ $? -ne 0 ]; then
    echo "Error: $error"
  fi
  echo -ne "\r\033[2K"
  echo -e "\r√ $output"
}

function create_folder {
  output_msg="Creating $1 on board"
  echo -n "$output_msg"
  error=$(mpremote mkdir "$1")
  # Print error message if return code is not 0
  if [ $? -ne 0 ]; then
    echo "Error: $error"
  fi
  echo -ne "\r\033[2K"
  echo -e "\r√ $output_msg"
}

function delete_folder {
  output_msg="Deleting $1 on board"
  echo -n "$output_msg"
  delete_folder="${PYTHON_HELPERS}delete_folder(\"/$1\")"
  error=$(mpremote exec "$delete_folder")
  # Print error message if return code is not 0
  if [ $? -ne 0 ]; then
    echo "Error: $error"
  fi
  echo -ne "\r\033[2K"
  echo -e "\r√ $output_msg"
}


function install_package {
  if [[ $1 == "" ]]; then
    echo "!!! No package path supplied !!!"
    exit 1
  fi
  # Name to display during installation
  PKGNAME=`basename $1`
  # Destination directory for the package on the board
  PKGDIR=`basename $1`
  # Source directory for the package on the host
  SRCDIR=`realpath .`
  # Board's library directory
  device_root="${PYTHON_HELPERS}print(get_root())"
  output=$(mpremote exec "$device_root")
  output=$(echo "$output" | tr -d '[:space:]')
  echo "$output"
  if [ "$output" == "/flash" ]; then
    echo "Board has root in /flash"
    # output=""
  fi
  LIBDIR="$output/lib"

  IFS=$'\n' read -rd '' -a package_files < <(find . -mindepth 1)
  items_count=${#package_files[@]}
  current_item=0
  for item_path in "${package_files[@]}"; do
    destination_subpath="${item_path//.\//$PKGNAME/}"
    if [ ! -f "$item_path" ] && [ ! -d "$item_path" ]; then
      echo -n "symlink file ignored"
      continue
    else
      current_item=$((current_item+1))
      # only delete and create package directory if it is the first item
      # if the script never made it here, it means no files were found
      if [ $current_item == 1 ]; then
        output_msg="Deleting $LIBDIR/$PKGDIR on board"
        if directory_exists "${LIBDIR}/${PKGDIR}"; then
          echo -n "$output_msg"
          delete_folder="${PYTHON_HELPERS}delete_folder(\"${LIBDIR}/${PKGDIR}\")"
          mpremote exec "$delete_folder"
        fi
        echo -ne "\r\033[2K"
        echo -e "\r√ $output_msg"
        create_folder "$LIBDIR/$PKGDIR"
      fi
      step_counter="[$(printf "%2d" $current_item)/$(printf "%2d" $items_count)] "
      echo -n "$step_counter"
      if [ -d "$item_path" ]; then
        create_folder "$LIBDIR/$destination_subpath"
      elif [ -f "$item_path" ]; then
        f_name=`basename $item_path`
        source_extension="${f_name##*.}"
        destination_extension=$source_extension
        clean_item_path="${item_path//.\//}"
        if [[ "$ext" == "mpy" && "$source_extension" == "py" ]]; then
          mpy-cross "$item_path"
          destination_extension=$ext
          copy_file ${clean_item_path%.*}.$destination_extension :$LIBDIR/${destination_subpath%.*}.$destination_extension
        else
          copy_file $clean_item_path :$LIBDIR/$destination_subpath
        fi
      fi
    fi


  done

  if [ "$ext" == "mpy" ]; then
    echo "cleaning up mpy files"
    rm $SRCDIR/*.mpy
  fi
  if [ $items_count -gt 0 ]; then
    echo -e "\n*** Package $PKGNAME installed successfully ***\n"  
  else
    echo -e "\n*** Nothing done: no files found in package $PKGNAME ***\n"
  fi
  
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

echo "Packages: ${packages[@]}"
# Start the installation process
echo "MicroPython Package Installer"
echo "-----------------------------"
echo "Packages:" 

for package in "${packages[@]}"; do
  echo "• `basename $package`"
done

if device_present == 0; then
  echo "No device found. Please connect a MicroPython board and try again."
  exit 1
fi

package_number=0
start_dir=`pwd`
for package in "${packages[@]}"; do
  echo "-----------------------------"
  # echo "Installing package: `basename $package`"
  package_number=$((package_number+1))
  echo "Installing `basename $package` [$package_number/${#packages[@]}]"
  package_dir=`realpath $package`
  find $package_dir -name ".DS_Store" -type f -delete
  cd $package_dir
  install_package `basename $package`
  cd $start_dir
done

if [ "$reset" = true ]; then
  echo "Resetting target board ..."
  mpremote reset
  exit 1
fi
