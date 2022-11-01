#! /bin/bash
# Copyright (C) 2020 KenHV
# Copyright (C) 2020 Starlight
# Copyright (C) 2021 CloudedQuartz
# Copyright (C) 2021 REIGNZ
# Copyright (C) 2021 rokuSENPAI
# Copyright (C) 2021 Yoriscape

# Config
DIR="${PWD}"
KERNELNAME="Vertigo"
AK_DIR="$DIR/anykernel3"
KERNEL_DIR="$DIR/alioth"
CLANG_DIR="$DIR/clang"
GCC="$DIR/aarch64-linux-android-4.9"
GCC32="$DIR/arm-linux-androideabi-4.9"
DEVICE="alioth"
DEFCONFIG="alioth_defconfig"
LOG="$KERNEL_DIR/error.log"
VERSION="0.1"

CHANGELOG=""

clone() {
    git clone https://github.com/VoidUI-Devices/kernel_xiaomi_sm8250.git $KERNEL_DIR 
    git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9 $GCC
    git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9 $GCC32
    git clone https://github.com/yoriscape/anykernel.git $AK_DIR
    git clone https://android.googlesource.com/platform/system/libufdt $DIR/scripts/ufdt/libufdt 
}


# Export 
ARCH="arm64"
SUBARCH="arm64"
export ARCH SUBARCH
export CROSS_COMPILE=$GCC/bin/aarch64-linux-android-
export CROSS_COMPILE_ARM32=$GCC32/bin/arm-linux-androideabi-
export KBUILD_BUILD_USER=user
export KBUILD_BUILD_HOST=user

# Path
PATH="$CLANG_DIR/bin:$GCC32/bin:$GCC/bin:${PATH}"

KERNEL_IMG=$KERNEL_DIR/out/arch/$ARCH/boot/Image.gz-dtb
KERNEL_DTBO=$KERNEL_DIR/out/arch/$ARCH/boot/dtbo.img

TG_CHAT_ID="-1001668882933"
TG_BOT_TOKEN="1859665924:AAESHBMsyW52PhKah0Y2_mzGKiqZw1QC-KI"
# End config

# Function definitions

# tg_sendinfo - sends text through telegram
tg_sendinfo() {
	curl -s "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
		-F parse_mode=html \
		-F text="${1}" \
		-F chat_id="${TG_CHAT_ID}" &> /dev/null
}

# tg_pushzip - uploads final zip to telegram
tg_pushzip() {
    curl -F document=@"$1"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
            -F chat_id=$TG_CHAT_ID \
            -F caption="$2" \
            -F parse_mode=html &> /dev/null
}

# tg_failed - uploads build log to telegram
tg_failed() {
    curl -F document=@"$LOG"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
        -F chat_id=$TG_CHAT_ID \
        -F parse_mode=html &> /dev/null
}

# build_setup - enter kernel directory and get info for caption.
# also removes the previous kernel image, if one exists.
build_setup() {
    cd "$KERNEL_DIR" || echo -e "\nKernel directory ($KERNEL_DIR) does not exist" || exit 1

    [[ ! -d out ]] && mkdir out
    [[ -f "$KERNEL_IMG" ]] && rm "$KERNEL_IMG"
	find . -name "*.dtb" -type f -delete
}

# build_config - builds .config file for device.
alioth_defconfig() {
	make O=out $1 -j$(nproc --all)
}
# build_kernel - builds defconfig and kernel image using llvm tools, while saving the output to a specified log location
# only use after runing build_setup()
build_kernel() {

    BUILD_START=$(date +"%s")
    make -j$(nproc --all) O=out \
                CROSS_COMPILE=$CROSS_COMPILE \
                CROSS_COMPILE_COMPACT=$CROSS_COMPILE_ARM32 \
                CC=$CLANG_DIR/bin/clang \
                CLANG_TRIPLE=aarch64-linux-gnu- Image.gz-dtb 2>&1  |& tee $LOG

    BUILD_END=$(date +"%s")
    DIFF=$((BUILD_END - BUILD_START))
}

# build_end - creates and sends zip
build_end() {

	if ! [ -a "$KERNEL_IMG" ]; then
        echo -e "\n> Build failed, sending logs to Telegram."
        tg_failed
        tg_buildtime
        exit 1
    fi
    
    python2 $DIR/scripts/ufdt/libufdt/utils/src/mkdtboimg.py  create $KERNEL_DIR/out/arch/arm64/boot/dtbo.img --page_size=4096 $KERNEL_DIR/out/arch/arm64/boot/dts/vendor/qcom/alioth-sm8250-overlay.dtbo
   
    
    echo -e "\n> Build successful! generating flashable zip..."
	cd "$AK_DIR" || echo -e "\nAnykernel directory ($AK_DIR) does not exist" || exit 1
	git clean -fd
	mv "$KERNEL_IMG" "$AK_DIR"/Image.gz-dtb
    mv "$KERNEL_DTBO" "$AK_DIR"/dtbo.img
	ZIP_NAME=$KERNELNAME-V0.1-Beta-$(date +%Y-%m-%d_%H%M).zip
	zip -r9 "$ZIP_NAME" ./* -x .git README.md ./*placeholder
	tg_pushzip "$ZIP_NAME" "Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code>"
	echo -e "\n> Sent zip through Telegram.\n> File: $ZIP_NAME"
}

# End function definitions
cd $KERNEL_DIR

COMMIT=$(git log --pretty=format:"%s" -1)
COMMIT_SHA=$(git rev-parse --short HEAD)
KERNEL_BRANCH=$(git rev-parse --abbrev-ref HEAD)

CAPTION=$(echo -e \
"HEAD: <code>$COMMIT_SHA: </code><code>$COMMIT</code>
Branch: <code>$KERNEL_BRANCH</code>")

tg_sendinfo "-- Build Triggered By Yoriscape --
$CHANGELOG
$CAPTION"

clone

# Ccache
echo -e ${blu}"CCACHE is enabled for this build"${txtrst}
export CCACHE_EXEC=$(which ccache)
export USE_CCACHE=1
export CCACHE_DIR=$DIR/ccache
ccache -M 70G

# Clean out dir
rm -rf $KERNEL_DIR/out
rm -rf $AK_DIR/Image.gz-dtb $AK_DIR/Vertigo*.zip  $AK_DIR/dtbo.img
mkdir -p $KERNEL_DIR/out
make O=out clean

# Build device 1
build_setup
alioth_defconfig $DEFCONFIG
build_kernel
build_end $DEVICE
