# shellcheck shell=bash
# vm — guest tools for the hypervisor (UTM on Apple Silicon first), so copy and
# paste, display resizing and time sync work, plus the UTM shared folder.

pa_register vm "VM guest tools (UTM/QEMU, VMware) and UTM shared folder" "amd64 arm64" mod_vm

# The hypervisor this runs under (kvm, qemu, vmware, apple…), or "none"
pa_vm_virt() {
  local virt=""
  pa_has systemd-detect-virt && virt=$(systemd-detect-virt --vm 2>/dev/null)
  printf '%s\n' "${virt:-none}"
}

pa_vm_guest_tools() {
  case "$1" in
    kvm|qemu)
      pa_info "Hypervisor: QEMU (UTM) — installing the QEMU guest agent and SPICE agent"
      pa_apt qemu-guest-agent spice-vdagent || return 1
      sudo systemctl start qemu-guest-agent >/dev/null 2>&1 || true   # starts once UTM's agent channel exists
      ;;
    apple)
      pa_info "Hypervisor: Apple Virtualization (UTM) — SPICE agent for the clipboard"
      pa_apt spice-vdagent || return 1
      ;;
    vmware)
      pa_info "Hypervisor: VMware — installing open-vm-tools"
      pa_apt open-vm-tools-desktop || return 1
      ;;
    none)
      pa_info "No hypervisor detected — skipping guest tools"
      ;;
    *)
      pa_warn "Hypervisor '$1' isn't handled — install its guest tools yourself"
      ;;
  esac
}

# UTM's shared directory appears as a virtio mount tag named "share": 9p
# (VirtFS) under the QEMU backend, virtiofs under Apple Virtualization. Mounted
# on demand at ~/utm-share; nofail keeps boot working when sharing is off.
pa_vm_share() {
  local virt="$1" fstype opts mnt="$HOME/utm-share" line
  case "$virt" in
    kvm|qemu)
      sudo modprobe 9pnet_virtio >/dev/null 2>&1   # the tag only shows once the driver is loaded
      grep -qx share /sys/bus/virtio/drivers/9pnet_virtio/*/mount_tag 2>/dev/null || {
        pa_info "No UTM shared folder (VirtFS) configured — skipping. See docs/UTM.md to add one."
        return 0; }
      fstype=9p; opts="trans=virtio,version=9p2000.L,rw,_netdev,nofail,x-systemd.automount" ;;
    apple)
      fstype=virtiofs; opts="rw,nofail,x-systemd.automount" ;;
    *) return 0 ;;
  esac
  mkdir -p "$mnt"
  line="share $mnt $fstype $opts 0 0"
  if grep -q "^share $mnt " /etc/fstab 2>/dev/null; then
    pa_info "UTM shared folder already in /etc/fstab ✓"
  else
    printf '%s  # periapsis\n' "$line" | sudo tee -a /etc/fstab >/dev/null || return 1
    sudo systemctl daemon-reload >/dev/null 2>&1
    pa_info "UTM shared folder will mount at $mnt"
  fi
}

mod_vm() {
  local virt rc=0
  virt=$(pa_vm_virt)
  pa_vm_guest_tools "$virt" || rc=1
  pa_vm_share "$virt" || { pa_warn "UTM shared folder not set up"; rc=1; }
  return $rc
}
