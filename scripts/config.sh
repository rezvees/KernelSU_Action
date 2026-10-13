#!/usr/bin/env bash
# Resolve the build configuration, validate it, and export it to later steps.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "(dirname "{BASH_SOURCE[0]}")/lib.sh"

CONFIG_FILE=\${CONFIG_ENV:-config.env}

# --------------------------------------------------------------- defaults ---

declare -A DEFAULTS=(
	[KERNEL_SOURCE]=""
	[KERNEL_SOURCE_BRANCH]=""
	[KERNEL_CONFIG]=""
	[KERNEL_IMAGE_NAME]="Image.gz-dtb"
	[ARCH]="arm64"
	[KERNEL_NAME]=""
	[ADD_LOCALVERSION_TO_FILENAME]="false"
	[EXTRA_CMDS]=""
	[CUSTOM_CMDS]=""

	# Toolchain
	[USE_CUSTOM_CLANG]="false"
	[CUSTOM_CLANG_SOURCE]=""
	[CUSTOM_CLANG_BRANCH]=""
	[CLANG_BRANCH]="main-kernel-2025"
	[CLANG_VERSION]="r547379"
	[USE_LLVM]="false"
	[ENABLE_GCC_ARM64]="false"
	[ENABLE_GCC_ARM32]="false"
	[USE_CUSTOM_GCC_64]="false"
	[CUSTOM_GCC_64_SOURCE]=""
	[CUSTOM_GCC_64_BRANCH]=""
	[CUSTOM_GCC_64_BIN]="aarch64-linux-android-"
	[USE_CUSTOM_GCC_32]="false"
	[CUSTOM_GCC_32_SOURCE]=""
	[CUSTOM_GCC_32_BRANCH]=""
	[CUSTOM_GCC_32_BIN]="arm-linux-androideabi-"

	# KernelSU
	[KSU_VARIANT]="none"
	[KSU_REF]=""
	[KSU_HOOK_MODE]="auto"
	[KSU_EXPECTED_SIZE]=""
	[KSU_EXPECTED_HASH]=""

	# Patches
	[ENABLE_SUSFS]="false"
	[SUSFS_REPO]="https://gitlab.com"
	[SUSFS_BRANCH]="auto"
	[ENABLE_PATH_UMOUNT]="false"
	[ENABLE_HIDE_STUFF]="false"
	[ENABLE_KPM]="false"

	# NetHunter / extra modules
	[ENABLE_NETHUNTER]="false"
	[NETHUNTER_SOURCE]=""
	[NETHUNTER_BRANCH]=""
	[NETHUNTER_MODULE_PATH]=""

	# Kconfig tweaks
	[ADD_KPROBES_CONFIG]="false"
	[ADD_OVERLAYFS_CONFIG]="false"
	[DISABLE_LTO]="false"
	[DISABLE_CC_WERROR]="false"
	[EXTRA_DEFCONFIG]=""

	# Packaging
	[USE_CUSTOM_ANYKERNEL3]="false"
	[CUSTOM_ANYKERNEL3_SOURCE]=""
	[CUSTOM_ANYKERNEL3_BRANCH]=""
	[NEED_DTBO]="false"
	[BUILD_BOOT_IMG]="false"
	[SOURCE_BOOT_IMAGE]=""

	# Runner
	[ENABLE_CCACHE]="true"
	[REMOVE_UNUSED_PACKAGES]="true"
)

# ------------------------------------------------------------- parsing ------

group "Resolving Build Configuration"

if [ -f "WORKSPACE/config/{CONFIG_FILE}" ]; then
	info "Loading profile presets from: config/\${CONFIG_FILE}"
	. "WORKSPACE/config/{CONFIG_FILE}"
elif [ -f "WORKSPACE/{CONFIG_FILE}" ]; then
	info "Loading configuration data from: \${CONFIG_FILE}"
	. "WORKSPACE/{CONFIG_FILE}"
else
	warn "No external target configuration profile found: \${CONFIG_FILE}. Relying on defaults."
fi

for key in "\${!DEFAULTS[@]}"; do
	val=""
	in_var="IN_\${key}"
	if [ -n "\${!in_var:-}" ]; then
		val="\${!in_var}"
		debug "Workflow dispatch option override: key='\${val}'"
	elif [ -n "\${!key:-}" ]; then
		val="\${!key}"
	else
		val="\({DEFAULTS[\)key]}"
	fi

	case "\${val}" in
		"true" | "TRUE" | "1" | "y" | "Y") val="true" ;;
		"false" | "FALSE" | "0" | "n" | "N") val="false" ;;
	esac

	export_env "key" "val"
done

ok "Environment variables mapped successfully."
summary "| Config Target | \`${KERNEL_CONFIG:-unspecified}\` |"
endgroup
