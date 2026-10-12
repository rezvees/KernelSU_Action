# KernelSU Action
#
# NetHunter can be bundled into the final AnyKernel3 zip without registering it
# as a KSU_VARIANT. NetHunter is a module/overlay payload, not a kernel source
# variant like kernelsu-next or resukisu. This keeps the workflow's KernelSU
# integration model intact while still allowing a nethunter or similar overlay
# to be added to the output package.
#
# ENABLE_NETHUNTER=true
# NETHUNTER_SOURCE=https://github.com/SherlockChiang/Nethunter_for_KernelSU
# NETHUNTER_BRANCH=master
# NETHUNTER_MODULE_PATH=
#
# The source can be a git repo, direct zip URL, or a local archive. When
# NETHUNTER_MODULE_PATH is blank, the entire extracted tree is copied into the
# flashable zip root. If it points at a directory like "system" or "module",
# only that subtree is merged in.
