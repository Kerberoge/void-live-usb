#!/bin/bash

cd /home/joe/virt/usb
. env

msg "Creating disk image ..."
dd if=/dev/zero of=void.img bs=1 count=0 seek=10G
losetup -P /dev/loop0 void.img

msg "Creating partition table ..."
echo -e 'label: gpt \n size=1M, type="BIOS boot" \n size=+' | sfdisk /dev/loop0

msg "Creating filesystem ..."
mkfs.ext4 -L Void /dev/loop0p2
msg "Mounting filesystem ..."
mount /dev/loop0p2 /mnt
msg "Copying files ..."
cp -ax rootfs/* /mnt

msg "Modifying /etc/fstab ..."
uuid=$(blkid /dev/loop0p2 | sed -E 's/.* UUID="([a-f0-9-]*)" .*/\1/')
echo "UUID=$uuid / ext4 defaults 0 1" >> /mnt/etc/fstab

msg "Mounting pseudo filesystems ..."
mount -t proc proc /mnt/proc
mount -t sysfs sys /mnt/sys
mount --rbind /dev /mnt/dev
mount --rbind /run /mnt/run

msg "Installing grub ..."
sed -Ei 's/(GRUB_TIMEOUT)=[0-9]*/\1=0/' /mnt/etc/default/grub
chroot /mnt /bin/bash << EOF
grub-install /dev/loop0 --target=i386-pc
grub-mkconfig -o /boot/grub/grub.cfg
EOF

msg "Unmounting filesystems and removing loop device ..."
umount -R /mnt
losetup -d /dev/loop0

msg "Changing owner of disk image ..."
chown joe:joe void.img
