#!/usr/bin/sh

jar=$1

declare -a groupIdKeywords=( \
  "Specification-Vendor" \
  "Implementation-Vendor-Id" \
  "Specification-Title" \
  "Bundle-SymbolicName" \
)
  #"Implementation-Vendor" \
  #"Implementation-Title" \
groupIdRegexp=$(echo "${groupIdKeywords[@]}" | sed "s/ /\\\|/g")
unzip -q -c $jar META-INF/MANIFEST.MF | grep "\($groupIdRegexp\)" | awk -F: '{print $NF}'
