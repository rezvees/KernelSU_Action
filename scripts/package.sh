#!/usr/bin/env bash
# Package build output: AnyKernel3 flashable zip and, optionally, a boot image.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KERNEL_DIR=${KERNEL_DIR:?KERNEL_DIR must be set}
WORKSPACE=${WORKSPACE:-$(cd "${KERNEL_DIR}/.." && pwd)}
ARCH=${ARCH:-arm64}
BOOT_OUT="${KERNEL_DIR}/out/arch/${ARCH}/boot"
AK3="${WORKSPACE}/AnyKernel3"

clone_module_source() {
	local src=${1:?module source required}
	local dir=${2:?target dir required}
	local branch=${3:-}

	if [[ "$src" == *.zip ]]; then
		fetch "$src" "${WORKSPACE}/module.zip"
		extract_archive "${WORKSPACE}/module.zip" "$dir"
		return 0
	fi

	if [[ "$src" == *git* ]] || [[ "$src" == https://* ]] || [[ "$src" == git@* ]]; then
		if [ -n "$branch" ]; then
			retry 3 git clone -q --depth=1 -b "$branch" "$src" "$dir" \
				|| die "failed to clone ${src} @ ${branch}"
		else
			retry 3 git clone -q --depth=1 "$src" "$dir" \
				|| die "failed to clone ${src}"
		fi
		return 0
	fi

	# Treat anything else as a direct archive URL.
	fetch "$src" "${WORKSPACE}/module.zip"
	extract_archive "${WORKSPACE}/module.zip" "$dir"
}

embed_nethunter() {
	is_true "${ENABLE_NETHUNTER:-false}" || return 0
	group "Embedding NetHunter module"

	local src=${NETHUNTER_SOURCE:?NETHUNTER_SOURCE required when ENABLE_NETHUNTER=true}
	local branch=${NETHUNTER_BRANCH:-}
	local module_path=${NETHUNTER_MODULE_PATH:-}
	local staged="${WORKSPACE}/nethunter_staged"
	local target="${AK3}/nethunter"

	rm -rf "$staged" "$target"
	clone_module_source "$src" "$staged" "$branch" || die "failed to fetch NetHunter source"

	if [ -n "$module_path" ]; then
		[ -d "${staged}/${module_path}" ] || die "module path '${module_path}' not found in NetHunter source"
		cp -a "${staged}/${module_path}" "$target"
	else
		# The common NetHunter module layout is a rootfs-like tree. Copy it as-is.
		cp -a "$staged" "$target"
	fi

	# If the module source contains a standard system/ tree, merge it into the
	# flashable zip root as expected by kernel module overlays.
	if [ -d "${target}/system" ]; then
		cp -a "${target}/system/." "${AK3}/"
		# keep a folder copy for debugging and manual recovery
		cp -a "${target}/system" "${AK3}/nethunter-system"
	fi

	ok "NetHunter files staged (${target})"
	endgroup
}

make_anykernel3() {
	group "Building AnyKernel3 package"
	rm -rf "$AK3"

	if is_true "${USE_CUSTOM_ANYKERNEL3:-false}"; then
		local src=${CUSTOM_ANYKERNEL3_SOURCE:?CUSTOM_ANYKERNEL3_SOURCE required}
		case "$src" in
			*.tar.gz | *.tgz)
				fetch "$src" "${WORKSPACE}/ak3.tar.gz"
				extract_archive "${WORKSPACE}/ak3.tar.gz" "$AK3" ;;
			*.zip)
				fetch "$src" "${WORKSPACE}/ak3.zip"
				extract_archive "${WORKSPACE}/ak3.zip" "$AK3" ;;
			*git*)
				retry 3 git clone -q --depth=1 ${CUSTOM_ANYKERNEL3_BRANCH:+-b "$CUSTOM_ANYKERNEL3_BRANCH"} \
					"$src" "$AK3" || die "failed to clone ${src}" ;;
			*)
				fetch "$src" "${WORKSPACE}/ak3.zip"
				extract_archive "${WORKSPACE}/ak3.zip" "$AK3" ;;
		esac
	else
		retry 3 git clone -q --depth=1 https://github.com "$AK3" \
			|| die "failed to clone AnyKernel3"
		sed -i 's/do.devicecheck=1/do.devicecheck=0/g' "${AK3}/anykernel.sh"
		sed -i 's!BLOCK=/dev/block/platform/omap/omap_hsmmc.0/by-name/boot;!BLOCK=auto;!g' "${AK3}/anykernel.sh"
		sed -i 's/IS_SLOT_DEVICE=0;/is_slot_device=auto;/g' "${AK3}/anykernel.sh"
	fi

	cp "${BOOT_OUT}/${KERNEL_IMAGE_NAME}" "${AK3}/" \
		|| die "kernel image missing at ${BOOT_OUT}/${KERNEL_IMAGE_NAME}"
	if is_true "${CHECK_DTBO_IS_OK:-false}"; then
		cp "${BOOT_OUT}/dtbo.img" "${AK3}/"
	fi

	embed_nethunter
	rm -rf "${AK3}/.git" "${AK3}/.github" "${AK3}/README.md"

	ok "AnyKernel3 package assembled"
	endgroup
}

# ========================================================
# EXECUTION ROUTINE & COMPRESSION ENGINE
# ========================================================

# 1. Trigger the package creation and overlay embedding
make_anykernel3

# 2. Compress the assembled structure into a flashable target format
group "Compressing AnyKernel3 output package"
cd "$AK3"

ZIP_NAME="OnePlus9R-Kernel-${KERNEL_VERSION:-4.19}_$(date +%Y%m%d-%H%M).zip"
info "Archiving build components into: ${ZIP_NAME}"

# Clean up older residual zips if present in the folder
rm -f ./*.zip

# Generate zip archive, ignoring documentation or structural git layers
zip -r9 "$ZIP_NAME" ./* -x .git\* README.md \
    || die "Failed to create compressed AnyKernel3 flashable package"

# Move the completed flashable payload zip back to the workspace root directory
mv "$ZIP_NAME" "${WORKSPACE}/"

ok "Package creation complete: ${WORKSPACE}/${ZIP_NAME}"
endgroup
