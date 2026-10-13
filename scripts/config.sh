#!/usr/bin/env bash
# Resolve the build configuration, validate it, and export it to later steps.
#
# Resolution order (last wins):
#   1. built-in defaults below
#   2. the config file named by CONFIG_ENV (default: config.env)
#   3. workflow_dispatch inputs, passed in as IN_<KEY> environment variables
#
# The old workflow parsed config.env with
#     grep -w "$KEY" config.env | head -n1 | cut -d= -f2
# which truncates any value containing '=', matches commented-out lines, and
# matches a key that merely appears as a substring of a comment. That is why
# EXTRA_CMDS had to use a ':' separator. Both forms are still accepted here,
# but parsing is now anchored and comment-aware, so '=' in values is fine.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONFIG_FILE=${CONFIG_ENV:-config.env}

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
	[SUSFS_REPO]="https://gitlab.com/simonpunk/susfs4ksu.git"
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

# ---------------------------------------------------------------- helpers ---

# strip surrounding quotes and trailing whitespace
_strip() {
	local s=$1
	# remove CR/LF at end
	s=$(printf '%s' "$s" | sed -e 's/\r$//' -e 's/[[:space:]]*$//')
	# remove surrounding quotes if present
	case "$s" in
		\"*\"|\'*\') s="${s:1:-1}" ;;
	esac
	printf '%s' "$s"
}

# Strip shell-style trailing comments while preserving '#' inside quoted values.
_strip_inline_comment() {
	local s=$1
	local ch prev
	local i in_single=0 in_double=0
	for ((i = 0; i < ${#s}; i++)); do
		ch="${s:i:1}"
		prev=""
		if (( i > 0 )); then prev="${s:i-1:1}"; fi

		if [[ "$ch" == "'" && $in_double -eq 0 ]]; then
			((in_single = 1 - in_single))
			continue
		fi
		if [[ "$ch" == '"' && $in_single -eq 0 ]]; then
			((in_double = 1 - in_double))
			continue
		fi
		if [[ "$ch" == '#' && $in_single -eq 0 && $in_double -eq 0 ]]; then
			if (( i == 0 )) || [[ "$prev" =~ [[:space:]] ]]; then
				s="${s:0:i}"
				break
			fi
		fi
	done
	printf '%s' "$s"
}

# read a single key from CONFIG_FILE (supports KEY=VALUE and KEY: VALUE)
read_key_from_file() {
	local key=$1 file=$2
	[ -f "$file" ] || return 1

	local line val=""
	while IFS= read -r line || [ -n "$line" ]; do
		line=${line%$'\r'}
		line="${line#"${line%%[![:space:]]*}"}"
		[ -z "$line" ] && continue
		[[ "$line" =~ ^# ]] && continue

		if [[ "$line" =~ ^${key}[[:space:]]*[:=][[:space:]]*(.*)$ ]]; then
			val=${BASH_REMATCH[1]}
			val=$(_strip_inline_comment "$val")
			val=$(_strip "$val")
		fi
	done <"$file"

	[ -n "$val" ] || return 1
	printf '%s' "$val"
	return 0
}

# ----------------------------------------------------------- resolution ---

group "Resolving configuration (defaults -> ${CONFIG_FILE} -> IN_ overrides)"

for key in "${!DEFAULTS[@]}"; do
	val=${DEFAULTS[$key]}

	if file_val=$(read_key_from_file "$key" "$CONFIG_FILE"); then
		val=$(_strip "$file_val")
	fi

	in_name="IN_${key}"
	if [ -n "${!in_name:-}" ]; then
		val=$(_strip "${!in_name}")
	fi

	export "${key}=$val"
	export_env "$key" "$val"
done

info "Resolved configuration (non-empty keys):"
for key in KERNEL_SOURCE KERNEL_SOURCE_BRANCH KERNEL_CONFIG ARCH KERNEL_IMAGE_NAME KERNEL_NAME \
           KSU_VARIANT KSU_REF KSU_HOOK_MODE EXTRA_CMDS CUSTOM_CMDS; do
	[ -n "${!key:-}" ] && info "  ${key}=${!key}"
done

endgroup

# -------------------------------------------------------------- validation ---

if [ -z "${KERNEL_CONFIG:-}" ]; then
	die "KERNEL_CONFIG is empty; set it in ${CONFIG_FILE} or pass via IN_KERNEL_CONFIG (workflow input 'config')"
fi

