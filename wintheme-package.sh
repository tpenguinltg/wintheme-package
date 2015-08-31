#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

WINTHEME_PREVIEW_PATH="${WINTHEME_PREVIEW_PATH:-previews}"
WINTHEME_RAW_PATH="${WINTHEME_RAW_PATH:-raw}"
WINTHEME_BRANDING_FILE="$(realpath ${WINTHEME_BRANDING_FILE:-branding.png})"

WINTHEME_CLEAN_BEFORE_PACKAGING=${WINTHEME_CLEAN_BEFORE_PACKAGING:-0}

# this script returns the number of packages that failed to be built
failed_count=0

# Check for missing programs
for f in {cabextract,lcab,zip}; do
  command -v "$f" > /dev/null || (echo "ERROR: no program called $f found! Aborting." >&2 && exit 127)
done

# TODO: support verbose/quiet mode

clean-package() {
  if [ $# -ne 1 ]; then
    echo ERROR: Incorrect usage >&2
    echo Usage: $0 theme-name >&2
    exit 1
  fi
  rm -rfv "$1" "$1.zip" "raw/$1"
}

list-unpackaged() {
  ziplist=$(mktemp)
  themepacklist=$(mktemp)
  unpackagedlist=$(mktemp)
  previewlist=$(mktemp)
  packageablelist=$(mktemp)


  # list all packaged themes
  for zip in *.zip; do
    basename "$zip" .zip >> "$ziplist"
  done

  # list all available themepacks
  for theme in raw/*.{,desk}themepack; do
    basename "${theme%.*themepack}" >> "$themepacklist"
  done
  sort "$themepacklist" -o "$themepacklist"

  # list all available previews
  for preview in previews/*.png; do
    basename "$preview" .png >> "$previewlist"
  done

  # list discrepancies
  grep -F -x -v -f "$ziplist" "$themepacklist" > "$unpackagedlist"

  # list packageable
  grep -F -x -f "$unpackagedlist" "$previewlist" | sed 's#^.*$#s/^&$/\&*/#' > "$packageablelist"

  # output unpackaged with packageable themes starred
  sed -f "$packageablelist" < "$unpackagedlist"

  # remove temporary files
  rm -f "$ziplist" "$themepacklist" "$unpackagedlist" "$previewlist" "$packageablelist"
}

list-packageable() {
  list-unpackaged | grep '\*$' | sed 's/\*$//'
}

show-help() {
  cat <<EOF
Repackage a Windows theme with branding and a preview image.

USAGE
    $0 [OPTIONS] -- "Theme name 1" ["Theme name 2" [...]]

OPTIONS
    -c PACKAGE
        Clean package. Pass for each package to clean
    -h
        Show this help message
    -f
        Clean each package before building (f for force)
    -l
        List unpackaged themes. Packageable themes will have a * at the end of their names
    -u
        Package packageable themes (u for unpackaged)
    --
        Stop processing options
EOF
}

OPTIND=1
while getopts c:hflu opt; do
  case $opt in
    c)
      clean-package "$OPTARG"
      ;;
    h)
      show-help
      ;;
    f)
      WINTHEME_CLEAN_BEFORE_PACKAGING=1
      ;;
    l)
      list-unpackaged
      ;;
    u)
      while read theme; do
        WINTHEME_CLEAN_BEFORE_PACKAGING=$WINTHEME_CLEAN_BEFORE_PACKAGING "$0" "$theme"
        failed_count=$((failed_count + $?))
      done < <(list-packageable)
      ;;
  esac
done

# shift remaining arguments
shift $((OPTIND -1))

# check for correct number of arguments
#if [ $# -ne 1 ]; then
#  echo ERROR: Incorrect usage >&2
#  echo Usage: $0 theme-name >&2
#  exit 1
#fi

for theme in "$@"; do

  if [ -f "$WINTHEME_RAW_PATH/$theme.themepack" ]; then
    themepack_ext="themepack"
  elif [ -f "$WINTHEME_RAW_PATH/$theme.deskthemepack" ]; then
    themepack_ext="deskthemepack"
  else
      echo "ERROR: themepack for \"$theme\" not found in \"$WINTHEME_RAW_PATH\"!" >&2
      echo Skipping $theme.
      ((failed_count++))
      continue
  fi

  # Check for missing files
  for f in {"$WINTHEME_PREVIEW_PATH/$theme.png","$WINTHEME_BRANDING_FILE"}; do
    if [ ! -f "$f" ]; then
      echo "ERROR: $f missing!" >&2
      echo Skipping $theme.
      ((failed_count++))
      continue 2
    fi
  done

  echo "Making package for $theme"
  echo

  # prompt to overwrite if package already built
  if [ -e "$theme.zip" ] && [ $WINTHEME_CLEAN_BEFORE_PACKAGING -eq 0 ]; then
    read -n1 -p "Package for $theme already built. Overwrite? [y/N] " overwrite
    echo
    if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
      echo Skipping $theme.
      continue
    fi
  fi

  # Clean package if specified
  if [ $WINTHEME_CLEAN_BEFORE_PACKAGING -ne 0 ]; then
    echo "Cleaning existing $theme package..."
    clean-package "$theme"
  fi

  # Extract themepack
  echo Extracting themepack...
  pushd raw > /dev/null
  mkdir -p "$theme/sources" && cd "$theme/sources"
  cabextract "../../$theme.$themepack_ext"
  # Rename .theme file to the full theme name
  mv "${theme:0:9}.theme" "$theme.theme" 2> /dev/null

  # Extract colors
  echo Saving colors to \'$(realpath ../../../colors)/$theme.txt\'...
  sed -n '/^\[Control Panel\\Colors\]/,/^\s*$/p' < "$theme.theme" | head -n-1 | tail -n+2 | sed 's/\s*;.*$//;/^\s*$/d' | sort > "../../../colors/$theme.txt"

  # Apply branding
  echo Applying branding...
  cp "$WINTHEME_BRANDING_FILE" ./
  sed -i 's/\[Theme\]/[Theme]\r\nBrandImage='"$(basename "$WINTHEME_BRANDING_FILE")"'/' "$theme.theme"

  # Repackage themepack
  echo Repackaging themepack...
  lcab -r * "../$theme.$themepack_ext"

  # Zip packaage
  echo Making ZIP package...
  popd > /dev/null
  mkdir "$theme"
  cp "$WINTHEME_RAW_PATH/$theme/$theme.$themepack_ext" "$theme/"
  cp "$WINTHEME_PREVIEW_PATH/$theme.png" "$theme/preview.png"
  test "$ADDITIONAL_PACKAGE_FILES" && cp -r $ADDITIONAL_PACKAGE_FILES "$theme/"
  zip -r "$theme.zip" "$theme"

  # Done
  echo
  echo Theme package created.

done

exit $failed_count
