#!/usr/bin/env bash
# Execute this at the base of the streamlink repo.

set -e # stop on error

command -v makensis > /dev/null 2>&1 || { echo >&2 "makensis is required to build the installer. Aborting."; exit 1; }
command -v pynsist > /dev/null 2>&1 || { echo >&2 "pynsist is required to build the installer. Aborting."; exit 1; }


# For travis nightly builds generate a version number with commit hash
if [ -n "${TRAVIS_BRANCH}" ] && [ -z "${TRAVIS_TAG}" ]; then
    STREAMLINK_VERSION=$(python -c 'import streamlink; print(streamlink.__version__)')
    STREAMLINK_INSTALLER="streamlink-${STREAMLINK_VERSION}-${TRAVIS_BUILD_NUMBER}-${TRAVIS_COMMIT:0:7}"
    STREAMLINK_VERSION="${STREAMLINK_VERSION}+${TRAVIS_COMMIT:0:7}"
else
    STREAMLINK_VERSION=$(python setup.py --version)
    STREAMLINK_INSTALLER="streamlink-${STREAMLINK_VERSION}"
fi

build_dir="$(pwd)/build"
nsis_dir="${build_dir}/nsis"
# get the dist directory from an environment variable, but default to the build/nsis directory
dist_dir="${STREAMLINK_INSTALLER_DIST_DIR:-$nsis_dir}"
mkdir -p "${build_dir}" "${dist_dir}" "${nsis_dir}"

echo "Building ${STREAMLINK_INSTALLER} (v${STREAMLINK_VERSION})..." 1>&2

cat > "${build_dir}/streamlink.cfg" <<EOF
[Application]
name=Streamlink
version=${STREAMLINK_VERSION}
entry_point=streamlink_cli.main:main
icon=../win32/doggo.ico

[Python]
version=3.5.2
format=bundled

[Include]
packages=requests
         streamlink
         streamlink_cli
pypi_wheels=pycryptodome==3.4.3

files=../win32/rtmpdump > \$INSTDIR
      ../win32/LICENSE.txt > \$INSTDIR

[Command streamlink]
entry_point=streamlink_cli.main:main

[Build]
directory=nsis
nsi_template=installer_tmpl.nsi
installer_name=${dist_dir}/${STREAMLINK_INSTALLER}.exe
EOF

cat >"${build_dir}/installer_tmpl.nsi" <<EOF
!include "FileFunc.nsh"
!include "TextFunc.nsh"
[% extends "pyapp_msvcrt.nsi" %]

[% block modernui %]
    ; let the user review all changes being made to the system first
    !define MUI_FINISHPAGE_NOAUTOCLOSE
    !define MUI_UNFINISHPAGE_NOAUTOCLOSE

    ; add checkbox for opening the documentation in the user's default web browser
    !define MUI_FINISHPAGE_RUN
    !define MUI_FINISHPAGE_RUN_TEXT "Open online manual in web browser"
    !define MUI_FINISHPAGE_RUN_FUNCTION "OpenDocs"
    !define MUI_FINISHPAGE_RUN_NOTCHECKED

    Function OpenDocs
        ExecShell "" "https://streamlink.github.io/cli.html"
    FunctionEnd

    ; add checkbox for editing the configuration file
    !define MUI_FINISHPAGE_SHOWREADME
    !define MUI_FINISHPAGE_SHOWREADME_TEXT "Edit configuration file"
    !define MUI_FINISHPAGE_SHOWREADME_FUNCTION "EditConfig"
    !define MUI_FINISHPAGE_SHOWREADME_NOTCHECKED

    Function EditConfig
        SetShellVarContext current
        Exec '"\$WINDIR\notepad.exe" "\$APPDATA\streamlink\streamlinkrc"'
        SetShellVarContext all
    FunctionEnd

    ; constants need to be defined before importing MUI
    [[ super() ]]
[% endblock %]

[% block install_files %]
    [[ super() ]]
    ; Install config file
    SetShellVarContext current # install the config file for the current user
    SetOverwrite off # config file we don't want to overwrite
    SetOutPath \$APPDATA\streamlink
    File /r "streamlinkrc"
    \${ConfigWrite} "\$APPDATA\streamlink\streamlinkrc" "rtmpdump=" "\$INSTDIR\rtmpdump\rtmpdump.exe" \$R0
    SetOverwrite ifnewer
    SetOutPath -
    SetShellVarContext all

    ; Add metadata
    ; hijack the install_files block for this
    WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\${PRODUCT_NAME}" "DisplayVersion" "${STREAMLINK_VERSION}"
    WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\${PRODUCT_NAME}" "Publisher" "Streamlink"
    WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\${PRODUCT_NAME}" "URLInfoAbout" "https://streamlink.github.io/"
    WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\${PRODUCT_NAME}" "HelpLink" "https://streamlink.github.io/"
	\${GetSize} "\$INSTDIR" "/S=0K" \$0 \$1 \$2
	IntFmt \$0 "0x%08X" \$0
	WriteRegDWORD HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\${PRODUCT_NAME}" "EstimatedSize" "\$0"
[% endblock %]

[% block install_shortcuts %]
    ; Remove shortcut from previous releases
    Delete "\$SMPROGRAMS\Streamlink.lnk"
[% endblock %]

[% block uninstall_shortcuts %]
    ; no shortcuts to be removed...
[% endblock %]
EOF

echo "Building Python 3 installer" 1>&2

# copy the streamlinkrc file to the build dir, we cannot use the Include.files property in the config file
# because those files will always overwrite, and for a config file we do not want to overwrite
cp "win32/streamlinkrc" "${nsis_dir}/streamlinkrc"
pynsist build/streamlink.cfg

# Make a copy of this build for the "latest" nightly
if [ -n "${TRAVIS_BRANCH}" ] && [ -z "${TRAVIS_TAG}" ]; then
    cp "${dist_dir}/${STREAMLINK_INSTALLER}.exe" "${dist_dir}/streamlink-latest.exe"
fi

echo "Success!" 1>&2
echo "The installer should be in ${dist_dir}." 1>&2
