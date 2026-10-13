#!/usr/bin/env bash
# Apply local source fixes/workarounds for known LineageOS sm8250 build issues.
# This script is idempotent: it only modifies files when the exact problem is
# detected. It is intentionally small and conservative.

set -euo pipefail

KERNEL_DIR=${1:-}
if [ -z "$KERNEL_DIR" ]; then
  echo "[x] usage: $0 <path-to-kernel-tree>" >&2
  exit 2
fi

# Ensure we operate on paths that exist
if [ ! -d "$KERNEL_DIR" ]; then
  echo "[x] kernel dir not found: $KERNEL_DIR" >&2
  exit 2
fi

# 1) Avoid macro collision in kernel/sched/core.c
CORE_C="$KERNEL_DIR/kernel/sched/core.c"
if [ -f "$CORE_C" ]; then
  if grep -q "^extern unsigned int sched_ravg_window;" "$CORE_C" && ! grep -q "#undef sched_ravg_window" "$CORE_C"; then
    echo "[*] Inserting #undef for sched_ravg_window in $CORE_C"
    # Replace the single declaration line with undef + declaration in place.
    # Use a portable awk to perform the substitution only for the first match.
    awk 'BEGIN{done=0}
      {
        if (!done && $0 ~ /^extern unsigned int sched_ravg_window;$/) {
          print "/* Avoid macro collision: ensure sched_ravg_window isn't macro-expanded here */";
          print "#undef sched_ravg_window";
          print $0;
          done=1; next
        }
        print $0
      }' "$CORE_C" >"${CORE_C}.tmp" && mv "${CORE_C}.tmp" "$CORE_C"
    echo "[+] patched $CORE_C"
  else
    echo "[.] no sched_ravg_window declaration requiring change in $CORE_C"
  fi
else
  echo "[!] $CORE_C not found; skipping"
fi

# 2) Provide trace prototypes to avoid implicit-declaration errors
SA_C="$KERNEL_DIR/kernel/sched_assist/sched_assist_common.c"
if [ -f "$SA_C" ]; then
  if ! grep -q "__trace_printk" "$SA_C" || ! grep -q "__trace_bprintk" "$SA_C"; then
    echo "[*] Ensuring trace helper prototypes exist in $SA_C"
    # Insert prototypes near the top after the initial include block. We'll
    # look for the first blank line after the last contiguous #include and
    # insert the prototypes there.
    awk 'BEGIN{inserted=0; included_block=1}
      {
        if (included_block && $0 ~ /^\s*#include/) { print $0; next }
        if (included_block && $0 ~ /^\s*$/) {
          # end of include block -> insert prototypes once
          if (!inserted) {
            print "#if !defined(__ASSEMBLY__)";
            print "/* Provide prototypes for internal trace helpers used by event_trace_printk */";
            print "int __trace_printk(const char *fmt, ...);";
            print "int __trace_bprintk(void *ip, const char *fmt, ...);";
            print "#endif";
            inserted=1;
          }
          included_block=0
        }
        print $0
      }
      END{ if (!inserted) { print "\n#if !defined(__ASSEMBLY__)"; print "/* Provide prototypes for internal trace helpers used by event_trace_printk */"; print "int __trace_printk(const char *fmt, ...);"; print "int __trace_bprintk(void *ip, const char *fmt, ...);"; print "#endif" } }' "$SA_C" >"${SA_C}.tmp" && mv "${SA_C}.tmp" "$SA_C"
    echo "[+] ensured prototypes in $SA_C"
  else
    echo "[.] trace prototypes already present in $SA_C"
  fi
else
  echo "[!] $SA_C not found; skipping"
fi

exit 0
