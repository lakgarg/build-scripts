#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Copyright (C) 2018 Yaroslav Furman (YaroST12)

# Fucking folders
kernel_dir="${PWD}"
builddir="${kernel_dir}/build"
# Fucking versioning
branch_name=$(git rev-parse --abbrev-ref HEAD)
last_commit=$(git rev-parse --verify --short=10 HEAD)
version="-${branch_name}/${last_commit}"
export KBUILD_BUILD_USER="yaro"
# Fucking arch and clang triple
export ARCH="arm64"
export CLANG_TRIPLE="aarch64-linux-gnu-"
# Fucking toolchains
GCC="${TTHD}/toolchains/aarch64-linux-gnu/bin/aarch64-linux-gnu-"
GCC_32="${TTHD}/toolchains/arm-linux-gnueabi/bin/arm-linux-gnueabi-"
CLANG="${TTHD}/toolchains/clang/clang-r383902/"
CT_BIN="${CLANG}/bin/"
CT="${CT_BIN}/clang"
export LD_LIBRARY_PATH=${CLANG}/lib64:$LD_LIBRARY_PATH

# Colors
NC='\033[0m'
RED='\033[0;31m'
LRD='\033[1;31m'
LGR='\033[1;32m'
YEL='\033[1;33m'

# CPUs
cpus=`expr $(nproc --all)`
cpus_lto=`expr $(nproc --all) / 2`

# Separator
SEP="######################################"

# Fucking die
function die()
{
	echo -e ${RED} ${SEP}
	echo -e ${RED} "${1}"
	echo -e ${RED} ${SEP}
	exit
}

function parse_parameters()
{
	PARAMS="${*}"
	# Default params
	BUILD_GCC=false
	BUILD_CLEAN=false
	BUILD_FULL_LTO=false
	#CONFIG_FILE="vendor/neutrino_defconfig"
	#CONFIG_FILE="andromeda_defconfig"
	CONFIG_FILE="raphael_defconfig"
	VERBOSE=false
	# Cleanup strings
	VERSION=""
	REVISION=""
	COMPILER_NAME=""
	objdir="${kernel_dir}/out"

	while [[ ${#} -ge 1 ]]; do
		case ${1} in
			"-g"|"--gcc")
				BUILD_GCC=true ;;
			"-c"|"--clean")
				BUILD_CLEAN=true ;;
			"-v"|"--verbose")
				VERBOSE=true ;;
			"-lto")
				BUILD_FULL_LTO=true ;;
            *) die "Invalid parameter specified!" ;;
		esac

		shift
	done
	echo -e ${LGR} ${SEP}
	echo -e ${LGR} "Compilation started${NC}"
}

# Formats the time for the end
function format_time()
{
	MINS=$(((${2} - ${1}) / 60))
	SECS=$(((${2} - ${1}) % 60))

	TIME_STRING+="${MINS}:${SECS}"

	echo "${TIME_STRING}"
}

function make_image()
{
	# After we run savedefconfig in sources folder
	if [[ -f ${kernel_dir}/.config && ${BUILD_CLEAN} == false ]]; then
		echo -e ${LGR} "Removing misplaced defconfig... ${NC}"
		make -s -j${cpus} mrproper
	fi
	# Needed to make sure we get dtb built and added to kernel image properly
	# Cleanup existing build files
	if [ ${BUILD_CLEAN} == true ]; then
		echo -e ${LGR} "Cleaning up mess... ${NC}"
	    rm -rf ${objdir}
		make -s -j${cpus} mrproper
	fi

	START=$(date +%s)
	echo -e ${LGR} "Generating Defconfig ${NC}"
	make -s -j${cpus} ARCH=${ARCH} O=${objdir} ${CONFIG_FILE}

	if [ ! $? -eq 0 ]; then
		die "Defconfig generation failed"
	fi

	if [ ${BUILD_FULL_LTO} == true ]; then
		echo -e ${RED} "Enabling full LTO ${NC}"
		./scripts/config --file ${objdir}/.config --disable CONFIG_THINLTO
	fi

	echo -n -e ${LGR} "Building image using${NC}"
	if [ ${BUILD_GCC} == true ]; then
		cd ${kernel_dir}
		echo -e ${LGR} "using GCC${NC}"
		make -s -j${cpus} CROSS_COMPILE=${GCC} CROSS_COMPILE_ARM32=${GCC_32} \
		O=${objdir} Image.gz-dtb
	else
		# major version, usually 3 numbers (8.0.5 or 6.0.1)
		VERSION=$($CT --version | grep -wom 1 "[0-99][0-99].[0-99].[0-99]")
		# revision, usually 6 numbers with 'r' before them.
		# can also have a letter at the end.
		REVISION=$($CT --version | grep -wom 1 "r[0-99]*[a-zA-Z0-9]")
		if [[ ${REVISION} ]]; then
			COMPILER_NAME="Clang-${VERSION}-${REVISION}"
		else
			COMPILER_NAME="Clang"
		fi
		echo -e ${YEL} "${COMPILER_NAME} ${NC}"
		cd ${kernel_dir}
		PATH=${CT_BIN}:${PATH} \
		make -s -j${cpus} CC="clang -ferror-limit=1" \
		AR="llvm-ar" \
		NM="llvm-nm" \
		OBJCOPY="llvm-objcopy" \
		OBJDUMP="llvm-objdump" \
		STRIP="llvm-strip" \
		CROSS_COMPILE=${GCC} \
		CROSS_COMPILE_ARM32=${GCC_32} \
		KBUILD_COMPILER_STRING="${COMPILER_NAME}" \
		O=${objdir} Image.gz-dtb
	fi

	completion "${START}" "$(date +%s)"
}

function completion()
{
	cd ${objdir}
	COMPILED_IMAGE=arch/arm64/boot/Image.gz-dtb
	TIME=$(format_time "${1}" "${2}")
	if [[ -f ${COMPILED_IMAGE} ]]; then
		mv -f ${COMPILED_IMAGE} ${builddir}/Image.gz-dtb
		echo -e ${LGR} "Build competed in" "${TIME}!"
		if [ ${VERBOSE} == true ]; then
			echo -e ${LGR} "Version: ${YEL}F1xy${version}"
			SIZE=$(ls -s ${builddir}/Image.gz-dtb | sed 's/ .*//')
			echo -e ${LGR} "Img size: ${YEL}${SIZE} kb${NC}"
		fi
		echo -e ${LGR} ${SEP}
	else
		echo -e ${RED} ${SEP}
		echo -e ${RED} "Something went wrong"
		echo -e ${RED} ${SEP}
	fi
}
parse_parameters "${@}"
make_image
cd ${kernel_dir}
