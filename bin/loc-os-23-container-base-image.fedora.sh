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

#########################################################################
#                   install-build-dependencies                          #
#########################################################################
# DESCRIPTION:                                                          #
#              Validate the installation of the buildah,deboostrap,dpkg #
#              and wget packages, install packages which are not        #
#              actually installed in the execution host.                #
#########################################################################
# PARAMETERS:  N/A                                                      #
#########################################################################
# RETURNS:     N/A                                                      #
#########################################################################
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

#########################################################################
#                   create-debian-base-system                           #
#########################################################################
# DESCRIPTION:                                                          #
#              Validates the existencie of the DEBIAN_BASE_SYSTEM_DIR   #
#              directory and creates if doesn't exist.                  #
#              Creates a Debian Base System File System and puts in the #
#              directory value of DEBIAN_BASE_SYSTEM_DIR variable       #
#              Uses the value of DEBIAN_BASE_SYSTEM_DIR and             #
#              DEBIAN_MIRROR_URL to determine the version and the origin#
#              packages for the target Debian Base System               #
#########################################################################
# PARAMETERS:  N/A                                                      #
#########################################################################
# RETURNS:     N/A                                                      #
#########################################################################
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

#########################################################################
#                   create-loc-os-base-image                            #
#########################################################################
# DESCRIPTION:                                                          #
#              Creates a base container image accoriding to the script  #
# https://gitlab.com/loc-os_linux/debian12-to-loc-os23/-/blob/main/debian12-to-loc-os23.sh#
#              Some steps are omited since the Base System doesnt have  #
#              certnain packages like apparmor. In specific cases       #
#              the permissions used by this image for the version       #
#              and package repositories changed from 777 to 755 for     #
#              security reasons. The installation of Kernel is          #
#              intentionally ommitted because in a container the Kernel #
#              is provided by the host                                  #
#########################################################################
# PARAMETERS:  N/A                                                      #
#########################################################################
# RETURNS:     N/A                                                      #
#########################################################################
function create-loc-os-base-image()
{
    # Create a new build container and mount its filesystem on the host
    NEW_CONTAINER=$(buildah from scratch)
    echo "Build Container ${NEW_CONTAINER} Created"
    NEW_CONTAINER_MNT=$(buildah mount ${NEW_CONTAINER})
    echo "Directory from Build Container ${NEW_CONTAINER} mounted in ${NEW_CONTAINER_MNT}"

    # Copy the Debian Base System to the Container Image File System
    echo "Copy Debian Base System into ${NEW_CONTAINER_MNT}"
    cp -pRv ${DEBIAN_BASE_SYSTEM_DIR}/* ${NEW_CONTAINER_MNT}

    # Configure the Debian Packages Repositories on the container image"
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

    # Installing of SysV init and delete of systemd"
    echo "Installing sysvinit"
    buildah run -t ${NEW_CONTAINER} apt -y install sysvinit-core sysvinit-utils

    # Set up the loc-os debian packages repositories
    echo "Configuring loc-os mirror"
    wget -O ${NEW_CONTAINER_MNT}/root/loc-os-keyring.deb ${LOCOS_KEYRING_URL}
    buildah run -t ${NEW_CONTAINER} dpkg -i /root/loc-os-keyring.deb
    rm -rf ${NEW_CONTAINER_MNT}/root/loc-os-keyring.deb
    echo "deb ${LOCOS_MIRROR_URL} ${LOCOS_CODENAME} main" > ${NEW_CONTAINER_MNT}${LOCOS_SOURCES_FILE}
    buildah run -t ${NEW_CONTAINER} apt update

    # Change the version files of the system from Debian to Loc-os
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

    # Deny the use or instllation of any systemd package
    echo "Creating ${NEW_CONTAINER_MNT}/etc/apt/preferences.d/00systemd file"
    cat << EOF > ${NEW_CONTAINER_MNT}/etc/apt/preferences.d/00systemd
Package: *systemd*:any
Pin: origin *
Pin-Priority: -1
EOF
    
    # Install and configure the lpkbuild package manager for loc-os
    echo "Configuring lpkgbuild"
    mkdir -pv ${NEW_CONTAINER_MNT}/opt/Loc-OS-LPKG/lpkgbuild/remove
    touch ${NEW_CONTAINER_MNT}/opt/Loc-OS-LPKG/lpkgbuild/remove/lpkgbuild-64.list
    wget -O ${NEW_CONTAINER_MNT}/sbin/lpkgbuild ${LOCOS_LPKGBUILD_URL}
    chmod +x ${NEW_CONTAINER_MNT}/sbin/lpkgbuild

    # Update SysV init with lpkbuild from loc-os sources
    # Note: At this point it is necessary to confirm the installation of the package, 
    #       since lpgkbuild does not have an option to assume the installation (For example -y in apt)
    echo "Updating SysV init"
    buildah run -t ${NEW_CONTAINER} apt -y install wget
    buildah run -t ${NEW_CONTAINER} lpkgbuild update
    buildah run -t ${NEW_CONTAINER} lpkgbuild install sysvinit-3.08
    rm -rf ${NEW_CONTAINER_MNT}/opt/Loc-OS-LPKG/lpkgbuild/remove/*

    # Install libeudev1 package
    echo "Installing libeudev1"
    buildah run -t ${NEW_CONTAINER} apt -y install libeudev1

    # Delete cache for apt in the image for storage optimization purpose.
    echo "Cleaning Cache"
    buildah run -t ${NEW_CONTAINER} apt clean
    buildah run -t ${NEW_CONTAINER} apt autoremove
    buildah run -t ${NEW_CONTAINER} apt autoclean

    # Setting up the default command used by the image (It poinyt to shell bash binary)
    echo "Setting CMD and Name label for image"
    buildah config --cmd /bin/bash  --label name=loc-os ${NEW_CONTAINER}

    # Create the image in a single layer
    echo "Commiting Image"
    buildah commit --squash ${NEW_CONTAINER} loc-os:${LOCOS_VERSION}
}

#########################################################################
#                            clean-workspace                            #
#########################################################################
# DESCRIPTION:                                                          #
#              Umount the Container Image File System, clean the        #
#              NEW_CONTAINER_MNT variable, delete the image builder     #
#              container and delete the Debian Base File System Dir     #
#########################################################################
# PARAMETERS:  N/A                                                      #
#########################################################################
# RETURNS:     N/A                                                      #
#########################################################################
function clean-workspace()
{
    echo "Umounting Directory ${NEW_CONTAINER_MNT}"
    buildah umount ${NEW_CONTAINER}
    unset NEW_CONTAINER_MNT
    echo "Removing Build Container ${NEW_CONTAINER}"
    buildah rm ${NEW_CONTAINER}
    rm -rf ${DEBIAN_BASE_SYSTEM_DIR}
}

#########################################################################
#                            main flow script                           #
#########################################################################
validate-execution-os;
validate-execution-user;
install-build-dependencies;
create-debian-base-system;
create-loc-os-base-image;
clean-workspace;