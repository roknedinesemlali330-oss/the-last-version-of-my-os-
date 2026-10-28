# Environment for the MyOS desktop session
export QS_ICON_THEME=Papirus
export MOZ_ENABLE_WAYLAND=1
# Software rendering for the shell: slower on paper, but stable on every machine
export QT_QUICK_BACKEND=software

CONF=/etc/myos/hyprland.conf

# Inside a virtual machine: lighter config and software cursor
if systemd-detect-virt -q; then
  CONF=/etc/myos/hyprland-vm.conf
  export WLR_NO_HARDWARE_CURSORS=1
  export WLR_RENDERER_ALLOW_SOFTWARE=1
fi

# Start the desktop on the first console (tty1)
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  if Hyprland -c "$CONF"; then
    exit 0
  else
    exec sway
  fi
fi
