#!/bin/bash
#########################################################################
#  _      _                                                     _       #
# | |    (_)                                    /\             (_)      #
# | |     _ _ __  _   ___  _____ _ __ ___      /  \   __ _ _ __ _  ___  #
# | |    | | '_ \| | | \ \/ / _ \ '__/ _ \    / /\ \ / _` | '__| |/ _ \ #
# | |____| | | | | |_| |>  <  __/ | | (_) |  / ____ \ (_| | |  | | (_) |#
# |______|_|_| |_|\__,_/_/\_\___|_|  \___/  /_/    \_\__, |_|  |_|\___/ #
#                                                     __/ |             #
#                                                    |___/              #
#########################################################################
# NAME: loc-os-23-container-base-image.fedora.sh                        #
# DESCRIPTION: Build a loc-os container image using buildah, debootstrap#
#              dpkgl and wget. Based on the script which converts a     #
#              GNU/Linux Debian to Loc-OS                               #
#########################################################################
# CHANGE LOG:                                                           #
# VERSION DATE          AUTHOR                        DESCRIPTION       #
# 1.0     14/DEC/2023   Jorge Varela (@linuxeroagrio) 1st Version       #
#########################################################################

#########################################################################
#                   ENVIRONMENT VARIABLES                               #
#########################################################################
# NAME: DESCRIPTION                                                     #
# DEBIAN_CODE_NAME:       The codename from Debian Base System          #
#                         (ex: bookworm)                                #
# DEBIAN_BASE_SYSTEM_DIR: The direcyory will be place for debian base   #
#                         system                                        #
# DEBIAN_MIRROR_URL:      The primary Mirror URL source of the packages #
#                         debian base system                            #
# NEW_CONTAINER:          Name of the builder container                 #
# NEW_CONTAINER_MNT:      Path of the container image mounted in the    #
#                         host                                          #
# LOCOS_MIRROR_URL:       Mirror Debian Package Repository for Loc-os   #
# LOCOS_VERSION:          Loc-os version to build                       #
# LOCOS_CODENAME:         Loc-os codename from version to build         #
# LOCOS_KEYRING_URL:      Loc-os Package Repository Keyring Url         #
# LOCOS_SOURCES_FILE:     Path file for Loc-os Deb Repository           #
# LOCOS_LPKGBUILD_URL:    URL for lpkbuild script                       #
#########################################################################
export DEBIAN_CODE_NAME="bookworm"
export DEBIAN_BASE_SYSTEM_DIR="/root/debian-${DEBIAN_CODE_NAME}-fs"
export DEBIAN_MIRROR_URL="http://deb.debian.org/debian"
export NEW_CONTAINER=""
export NEW_CONTAINER_MNT=""
export LOCOS_MIRROR_URL="http://br.loc-os.com"
export LOCOS_VERSION="23"
export LOCOS_CODENAME="contutti"
export LOCOS_KEYRING_URL="${LOCOS_MIRROR_URL}/pool/main/l/loc-os-23-archive-keyring/loc-os-23-archive-keyring_23.12.11_all.deb"
export LOCOS_SOURCES_FILE="/etc/apt/sources.list.d/loc-os.list"
export LOCOS_LPKGBUILD_URL="https://gitlab.com/loc-os_linux/lpkgbuild/-/raw/main/lpkgbuild"

#########################################################################
#                   validate-execution-os                               #
#########################################################################
# DESCRIPTION:                                                          #
#              Validate if the Operating System is Fedora, exit 1 if    #
#              not                                                      #
#########################################################################
# PARAMETERS:  N/A                                                      #
#########################################################################
# RETURNS:     N/A                                                      #
#########################################################################
function validate-execution-os()
{
  if [ "$(grep -w ID /etc/os-release | awk -F'=' '{print $2}')" != "fedora" ]
  then
    echo "Execute this script from fedora OS"
    exit 1;
  fi
}

#########################################################################
#                   validate-execution-user                             #
#########################################################################
# DESCRIPTION:                                                          #
#              Validate if the execution user is root, exit 1 if        #
#              not                                                      #
#########################################################################
# PARAMETERS:  N/A                                                      #
#########################################################################
# RETURNS:     N/A                                                      #
#########################################################################
function validate-execution-user()
{
    if [ "${UID}" -ne "0" ]
    then
      echo "Execute this script with root user"
      exit 1;
    fi
}

function install-build-dependencies()
{
    PACKAGES=""
    for PACKAGE in "/usr/bin/buildah" "/usr/sbin/debootstrap" "/usr/bin/dpkg" "/usr/bin/wget"
    do
      if [ ! -f "${PACKAGE}" ]
      then
        PACKAGES="${PACKAGES} $(basename ${PACKAGE})"
      fi
    done

    if [ -n "${PACKAGES}" ]
    then
      echo "Build Packages to Be Installed are ${PACKAGES}"
      dnf install -y ${PACKAGES}
    else
      echo "All build packages are present in this System"
    fi
}

function create-debian-base-system()
{
    if [ -d "${DEBIAN_BASE_SYSTEM_DIR}" ]
    then
      echo "Directory ${DEBIAN_BASE_SYSTEM_DIR} already exists, deleting"
      rm -rf ${DEBIAN_BASE_SYSTEM_DIR}
    fi
    
    echo "Creating Debian Base System"
    mkdir -pv ${DEBIAN_BASE_SYSTEM_DIR}
    debootstrap ${DEBIAN_CODE_NAME} ${DEBIAN_BASE_SYSTEM_DIR} ${DEBIAN_MIRROR_URL}
}

function create-loc-os-base-image()
{
    NEW_CONTAINER=$(buildah from scratch)
    echo "Build Container ${NEW_CONTAINER} Created"
    NEW_CONTAINER_MNT=$(buildah mount ${NEW_CONTAINER})
    echo "Directory from Build Container ${NEW_CONTAINER} mounted in ${NEW_CONTAINER_MNT}"

    echo "Copy Debian Base System into ${NEW_CONTAINER_MNT}"
    cp -pRv ${DEBIAN_BASE_SYSTEM_DIR}/* ${NEW_CONTAINER_MNT}

    echo "Configuring Mirror Packages"
    echo "Installing ca-certificates package"
    buildah run -t ${NEW_CONTAINER} apt -y install ca-certificates
    echo "Editing ${NEW_CONTAINER_MNT}/etc/apt/sources.list file"
    cat << EOF > ${NEW_CONTAINER_MNT}/etc/apt/sources.list
# See https://wiki.debian.org/SourcesList for more information.
deb http://deb.debian.org/debian ${DEBIAN_CODE_NAME} main contrib non-free-firmware
#deb-src http://deb.debian.org/debian ${DEBIAN_CODE_NAME} main

deb http://deb.debian.org/debian ${DEBIAN_CODE_NAME}-updates main
#deb-src http://deb.debian.org/debian ${DEBIAN_CODE_NAME}-updates main

deb http://security.debian.org/debian-security/ ${DEBIAN_CODE_NAME}-security main
#deb-src http://security.debian.org/debian-security/ ${DEBIAN_CODE_NAME}-security main
EOF

    echo "Installing sysvinit"
    buildah run -t ${NEW_CONTAINER} apt -y install sysvinit-core sysvinit-utils

    echo "Configuring loc-os mirror"
    wget -O ${NEW_CONTAINER_MNT}/root/loc-os-keyring.deb ${LOCOS_KEYRING_URL}
    buildah run -t ${NEW_CONTAINER} dpkg -i /root/loc-os-keyring.deb
    rm -rf ${NEW_CONTAINER_MNT}/root/loc-os-keyring.deb
    echo "deb ${LOCOS_MIRROR_URL} ${LOCOS_CODENAME} main" > ${NEW_CONTAINER_MNT}${LOCOS_SOURCES_FILE}
    buildah run -t ${NEW_CONTAINER} apt update

    echo "Creating ${NEW_CONTAINER_MNT}/etc/lsb-release file"
    cat << EOF > ${NEW_CONTAINER_MNT}/etc/lsb-release
PRETTY_NAME='Loc-OS Linux ${LOCOS_VERSION}'
DISTRIB_ID=Loc-OS
DISTRIB_RELEASE=${LOCOS_VERSION}
DISTRIB_CODENAME='Con Tutti'
DISTRIB_DESCRIPTION='Loc-OS Linux ${LOCOS_VERSION}'
EOF

echo "Creating ${NEW_CONTAINER_MNT}/etc/issue file"
    cat << EOF > ${NEW_CONTAINER_MNT}/etc/issue
Loc-OS Linux ${LOCOS_VERSION} \n \l
EOF

    echo "Creating ${NEW_CONTAINER_MNT}/etc/apt/preferences.d/00systemd file"
    cat << EOF > ${NEW_CONTAINER_MNT}/etc/apt/preferences.d/00systemd
Package: *systemd*:any
Pin: origin *
Pin-Priority: -1
EOF

    echo "Configuring lpkgbuild"
    mkdir -pv ${NEW_CONTAINER_MNT}/opt/Loc-OS-LPKG/lpkgbuild/remove
    touch ${NEW_CONTAINER_MNT}/opt/Loc-OS-LPKG/lpkgbuild/remove/lpkgbuild-64.list
    wget -O ${NEW_CONTAINER_MNT}/sbin/lpkgbuild ${LOCOS_LPKGBUILD_URL}
    chmod +x ${NEW_CONTAINER_MNT}/sbin/lpkgbuild

    echo "Updating SysV init"
    buildah run -t ${NEW_CONTAINER} apt -y install wget
    buildah run -t ${NEW_CONTAINER} lpkgbuild update
    buildah run -t ${NEW_CONTAINER} lpkgbuild install sysvinit-3.08
    rm -rf ${NEW_CONTAINER_MNT}/opt/Loc-OS-LPKG/lpkgbuild/remove/*

    echo "Installing libeudev1"
    buildah run -t ${NEW_CONTAINER} apt -y install libeudev1

    echo "Cleaning Cache"
    buildah run -t ${NEW_CONTAINER} apt clean
    buildah run -t ${NEW_CONTAINER} apt autoremove
    buildah run -t ${NEW_CONTAINER} apt autoclean

    echo "Setting CMD and Name label for image"
    buildah config --cmd /bin/bash  --label name=loc-os ${NEW_CONTAINER}

    echo "Commiting Image"
    buildah commit --squash ${NEW_CONTAINER} loc-os:${LOCOS_VERSION}
}

function clean-workspace()
{
    echo "Umounting Directory ${NEW_CONTAINER_MNT}"
    buildah umount ${NEW_CONTAINER}
    unset NEW_CONTAINER_MNT
    echo "Removing Build Container ${NEW_CONTAINER}"
    buildah rm ${NEW_CONTAINER}
    rm -rf ${DEBIAN_BASE_SYSTEM_DIR}
}

validate-execution-os;
validate-execution-user;
install-build-dependencies;
create-debian-base-system;
create-loc-os-base-image;
clean-workspace;