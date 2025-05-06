#!/bin/sh

cd ~/virt/usb
qemu-system-x86_64 \
		-enable-kvm \
		-cpu host \
		-smp 4 \
		-m 4G \
		-drive file=void.img,if=virtio,format=raw \
		-net nic \
		-net user,hostfwd=tcp::2225-:22 \
		-vga virtio \
		-audiodev pipewire,id=snd0 \
		-device virtio-sound-pci,audiodev=snd0 \
		-display gtk,show-cursor=on \
		"$@" &
