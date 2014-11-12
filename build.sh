#!/bin/sh -e
#
# Copyright (c) 2010-2014 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

DIR=$PWD
TEMPDIR=$(mktemp -d)

ARCH=$(uname -m)
SYST=$(uname -n)

# Number of jobs for make to run in parallel.
if [ $(which nproc) ] ; then
	NUMJOBS=$(nproc)
else
	NUMJOBS=1
fi

. ./version.sh

#Debian 7 (Wheezy): git version 1.7.10.4 and later needs "--no-edit"
unset git_opts
git_no_edit=$(LC_ALL=C git help pull | grep -m 1 -e "--no-edit" || true)
if [ ! "x${git_no_edit}" = "x" ] ; then
	GIT_OPTS="--no-edit"
fi

mkdir -p ${DIR}/git/
mkdir -p ${DIR}/dl/
mkdir -p ${DIR}/deploy/

rm -rf ${DIR}/deploy/latest-bootloader.log || true

#export MIRROR="http://example.com"
#./build.sh
if [ ! "${MIRROR}" ] ; then
	MIRROR="http:"
fi

WGET="wget --no-check-certificate -c --directory-prefix=${DIR}/dl/"

dl_gcc_generic () {
	site="https://releases.linaro.org"
	if [ ! -f ${DIR}/dl/${datestamp} ] ; then
		echo "Installing: ${toolchain_name}"
		echo "-----------------------------"
		${WGET} ${site}/${version}/${filename}
		if [ -d ${DIR}/dl/${directory} ] ; then
			rm -rf ${DIR}/dl/${directory} || true
		fi
		tar xf ${DIR}/dl/${filename} -C ${DIR}/dl/
		touch ${DIR}/dl/${datestamp}
	fi

	if [ "x${ARCH}" = "xarmv7l" ] ; then
		#using native gcc
		CC=
	else
		if [ -f /usr/bin/ccache ] ; then
			CC="ccache ${DIR}/dl/${directory}/${binary}"
		else
			CC="${DIR}/dl/${directory}/${binary}"
		fi
	fi
}

gcc_linaro_gnueabihf_4_9 () {
		#
		#https://releases.linaro.org/14.09/components/toolchain/binaries/gcc-linaro-arm-linux-gnueabihf-4.9-2014.09_linux.tar.xz
		#
		gcc_version="4.9"
		release="2014.09"
		toolchain_name="gcc-linaro-arm-linux-gnueabihf"
		version="14.09/components/toolchain/binaries"
		directory="${toolchain_name}-${gcc_version}-${release}_linux"
		filename="${directory}.tar.xz"
		datestamp="${release}-${toolchain_name}"

		binary="bin/arm-linux-gnueabihf-"

	dl_gcc_generic
}

git_generic () {
	echo "Starting ${project} build for: ${BOARD}"
	echo "-----------------------------"

	if [ ! -f ${DIR}/git/${project}/.git/config ] ; then
		git clone git://github.com/RobertCNelson/${project}.git ${DIR}/git/${project}/
	fi

	cd ${DIR}/git/${project}/
	git pull ${GIT_OPTS} || true
	git fetch --tags || true
	cd -

	if [ -d ${DIR}/scratch/${project} ] ; then
		rm -rf ${DIR}/scratch/${project} || true
	fi

	mkdir -p ${DIR}/scratch/${project}
	git clone --shared ${DIR}/git/${project} ${DIR}/scratch/${project}

	cd ${DIR}/scratch/${project}

	if [ "${GIT_SHA}" ] ; then
		echo "Checking out: ${GIT_SHA}"
		git checkout ${GIT_SHA} -b ${project}-scratch
	fi
}

git_cleanup () {
	cd ${DIR}/

	rm -rf ${DIR}/scratch/${project} || true

	echo "${project} build completed for: ${BOARD}"
	echo "-----------------------------"
}

halt_patching_uboot () {
	pwd
	echo "-----------------------------"
	echo "make ARCH=arm CROSS_COMPILE="${CC}" ${UBOOT_CONFIG}"
	echo "make ARCH=arm CROSS_COMPILE="${CC}" ${BUILDTARGET}"
	echo "-----------------------------"
	exit
}

file_save () {
	cp -v ./${filename_search} ${DIR}/${filename_id}
	md5sum=$(md5sum ${DIR}/${filename_id} | awk '{print $1}')
	check=$(ls "${DIR}/${filename_id}#*" 2>/dev/null | head -n 1)
	if [ "x${check}" != "x" ] ; then
		rm -rf "${DIR}/${filename_id}#*" || true
	fi
	touch ${DIR}/${filename_id}_${md5sum}
	echo "${BOARD}#${MIRROR}/${filename_id}#${md5sum}" >> ${DIR}/deploy/latest-bootloader.log
}

build_u_boot () {
	project="u-boot"
	git_generic

	make ARCH=arm CROSS_COMPILE="${CC}" distclean
	UGIT_VERSION=$(git describe)

	uboot_patch_dir="${uboot_stable}"
	if [ "${stable}" ] ; then
		#halt_patching_uboot

		#TI:
		git am "${DIR}/patches/${uboot_patch_dir}/0001-am335x_evm-uEnv.txt-bootz-n-fixes.patch"
		if [ "x${BOARD}" = "xam335x_boneblack" ] ; then
			git am "${DIR}/patches/${uboot_patch_dir}/0002-NFM-Production-eeprom-assume-device-is-BeagleBone-Bl.patch"
		fi
		git am "${DIR}/patches/${uboot_patch_dir}/0003-enable-uSOP-u-boot-loading-through-network.patch"
		git am "${DIR}/patches/${uboot_patch_dir}/0001-omap3_beagle-uEnv.txt-bootz-n-fixes.patch"
		git am "${DIR}/patches/${uboot_patch_dir}/0001-omap4_common-uEnv.txt-bootz-n-fixes.patch"
		git am "${DIR}/patches/${uboot_patch_dir}/0001-omap5_common-uEnv.txt-bootz-n-fixes.patch"
	fi

	if [ "x${BOARD}" = "xbeagle_x15_alpha" ] ; then
		git pull --no-edit https://github.com/RobertCNelson/u-boot-boards.git v2014.07_x15-alpha
	fi

	unset BUILDTARGET

	if [ -f "${DIR}/stop.after.patch" ] ; then
		echo "-----------------------------"
		pwd
		echo "-----------------------------"
		echo "make ARCH=arm CROSS_COMPILE="${CC}" ${UBOOT_CONFIG}"
		echo "make ARCH=arm CROSS_COMPILE="${CC}" ${BUILDTARGET}"
		echo "-----------------------------"
		exit
	fi

	uboot_filename="${BOARD}-${UGIT_VERSION}${RELEASE_VER}"

	mkdir -p ${DIR}/deploy/${BOARD}

	unset pre_built
	if [ -f ${DIR}/deploy/${BOARD}/u-boot-${uboot_filename}.imx ] ; then
		pre_built=1
	fi

	if [ -f ${DIR}/deploy/${BOARD}/u-boot-${uboot_filename}.sb ] ; then
		pre_built=1
	fi

	if [ -f ${DIR}/deploy/${BOARD}/MLO-${uboot_filename} ] ; then
		pre_built=1
	fi

	if [ -f ${DIR}/deploy/${BOARD}/u-boot-${uboot_filename}.sunxi ] ; then
		pre_built=1
	fi

	if [ -f ${DIR}/deploy/${BOARD}/u-boot-${uboot_filename}.bin ] ; then
		pre_built=1
	fi

	if [ -f ${DIR}/force_rebuild ] ; then
		unset pre_built
	fi

	if [ ! "${pre_built}" ] ; then
		make ARCH=arm CROSS_COMPILE="${CC}" ${UBOOT_CONFIG}
		echo "Building ${project}: ${uboot_filename}"
		echo "-----------------------------"
		make ARCH=arm CROSS_COMPILE="${CC}" -j${NUMJOBS} ${BUILDTARGET}
		echo "-----------------------------"

		unset UBOOT_DONE

		#SPL based targets, need MLO and u-boot.img from u-boot
		if [ ! "${UBOOT_DONE}" ] && [ -f ${DIR}/scratch/${project}/MLO ] && [ -f ${DIR}/scratch/${project}/u-boot.img ] ; then
			filename_search="MLO"
			filename_id="deploy/${BOARD}/MLO-${uboot_filename}"
			file_save

			filename_search="u-boot.img"
			filename_id="deploy/${BOARD}/u-boot-${uboot_filename}.img"
			file_save

                        filename_search="spl/u-boot-spl.bin"
                        filename_id="deploy/${BOARD}/u-boot-spl-${uboot_filename}.bin"
                        file_save 

			UBOOT_DONE=1
		fi

		#Just u-boot.bin
		if [ ! "${UBOOT_DONE}" ] && [ -f ${DIR}/scratch/${project}/u-boot.bin ] ; then
			filename_search="u-boot.bin"
			filename_id="deploy/${BOARD}/u-boot-${uboot_filename}.bin"
			file_save
			UBOOT_DONE=1
		fi
	else
		echo "-----------------------------"
		echo "Skipping Binary Build: as [${uboot_filename}] was previously built."
		echo "To override skipping(and force rebuild): [touch force_rebuild]"
		echo "-----------------------------"
	fi

	git_cleanup
}

cleanup () {
	unset GIT_SHA
	unset transitioned_to_testing
}

build_uboot_stable () {
	if [ "x${transitioned_to_testing}" = "x" ] ; then
		stable=1
		if [ "${uboot_stable}" ] ; then
			GIT_SHA=${uboot_stable}
			build_u_boot
		fi
		unset stable
	fi
}

am335x_boneblack_flasher () {
	cleanup
	#transitioned_to_testing="true"

	BOARD="am335x_boneblack"
	UBOOT_CONFIG="am335x_evm_defconfig"
	gcc_linaro_gnueabihf_4_9
	build_uboot_stable
	#build_uboot_testing
	#build_uboot_latest
}

x15_alpha () {
	cleanup
	#transitioned_to_testing="true"

	BOARD="beagle_x15_alpha"
	UBOOT_CONFIG="beagle_x15_config"
	gcc_linaro_gnueabihf_4_9
	GIT_SHA="524123a70761110c5cf3ccc5f52f6d4da071b959"
	build_u_boot
}

am335x_boneblack_flasher
