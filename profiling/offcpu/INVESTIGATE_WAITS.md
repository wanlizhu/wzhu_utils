# Investigating futex, GPU, and Wayland waits

`perf lock` only reports kernel mutex/rwsem/spinlock. Most application blocking (futex, GPU, Wayland) does **not** show there. Use the following.

## 1. Off-CPU flamegraph (main tool)

- **File:** `$HOME/<comm>_waitgraph.svg` (from `run-offcpu-profiling.sh`).
- **What it shows:** Where the process spent time **waiting** (off CPU), with kernel and userspace stacks.
- **How to use:**
  - Open the SVG and search for `futex` to see futex wait stacks.
  - Search for `drm_`, `amdgpu_`, `i915`, `nouveau` for GPU driver waits.
  - Search for `wayland`, `wl_`, `egl`, `glX` for display/GPU API waits.
- **Interpretation:** Wide or tall frames = more time waiting there. The stack under the frame is the call path that led to the wait.

## 2. Wakers file (who wakes you)

- **File:** `$HOME/<comm>_wakers.txt`.
- **What it shows:** For each wakeup, which PID/process woke the target (e.g. Xwayland, compositor, swapper).
- **How to use:** The summary in the script output (top 3 wakers with %) tells you the main sources of wakeups. High % from Xwayland/compositor → likely Wayland/display related; from swapper → often timer or interrupt; from same process → internal threading.

## 3. Futex-specific

- **Off-CPU graph:** Look for `futex_wait`, `futex_wait_queue_me`, `__futex_sleep`. The userspace stack above shows which lock or condition (e.g. Wayland, glib, your code).
- **Optional – trace futex syscalls:**
  ```bash
  sudo bpftrace -e 'tracepoint:syscalls:sys_enter_futex /pid == TARGET/ { printf("%s\n", kstack); }'
  ```
  Or use `strace -e futex -p <pid>` for a short capture (noisy).

## 4. GPU waits

- **Off-CPU graph:** Look for frames in the GPU driver: `amdgpu_`, `i915_`, `nouveau_`, `drm_`, or `ioctl` with a driver in the stack. That is time blocked on the GPU or in the kernel GPU path.
- **Complementary tools:** Vendor profilers (Radeon GPU Profiler, Nvidia Nsight Graphics) for GPU-side timing; `intel_gpu_top` / `radeontop` for GPU utilization.

## 5. Wayland / display

- Wayland uses futex + IPC. So:
  - **Off-CPU:** Look for `futex_*` plus `wayland`, `wl_`, or compositor libs in the stack.
  - **Wakers:** If Xwayland or the compositor is a top waker, most of that is display-related wakeups.
- **Compositor side:** Profile the compositor (e.g. mutter, kwin) with the same off-CPU script to see where it blocks and when it wakes clients.

## Quick checklist

| Wait type   | Where to look                          |
|------------|----------------------------------------|
| Futex      | Off-CPU flamegraph (futex_* + userspace stack) |
| GPU        | Off-CPU flamegraph (drm_*, *gpu*, ioctl) + vendor GPU tools |
| Wayland   | Off-CPU (futex + wayland/wl_*) + wakers (Xwayland/compositor %) |
