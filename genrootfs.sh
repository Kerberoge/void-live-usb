#!/bin/bash

TARGET_DIR=/home/joe/virt/usb/rootfs

VERSION=20240314
ARCH=x86_64
ROOTFS_FILENAME=void-${ARCH}-ROOTFS-${VERSION}.tar.xz
PUBKEY_URL=https://raw.githubusercontent.com/void-linux/void-packages/master/srcpkgs/void-release-keys/files/void-release-${VERSION}.pub
SIG_URL=https://repo-default.voidlinux.org/live/current/sha256sum.sig
SUMS_URL=https://repo-default.voidlinux.org/live/current/sha256sum.txt
ROOTFS_URL=https://repo-default.voidlinux.org/live/current/${ROOTFS_FILENAME}

. env

[[ $(whoami) == "root" ]] || die "Script needs to be run as root!"

mkdir -p $TARGET_DIR
if [[ -n $(ls -A $TARGET_DIR) ]]; then
	msg "Target directory is not empty, assuming the rootfs has already been unpacked."
else
	if [[ -r void.tar.xz ]]; then
		msg "Rootfs archive already present, skipping download and integrity check."
	else
		msg "Downloading public key ..."
		curl $PUBKEY_URL -s -o key.pub
		msg "Downloading signatures ..."
		curl $SIG_URL -s -o sums.sig
		msg "Downloading sums ..."
		curl $SUMS_URL -s -o sums.txt

		msg "Verifying authenticity ..."
		/usr/bin/minisign -V -p key.pub -x sums.sig -m sums.txt
		[[ $? -gt 0 ]] && die "Authenticity verification failed! Aborting."
		msg "Authenticity verification succeeded!"
		rm key.pub sums.sig

		msg "Downloading rootfs ..."
		curl $ROOTFS_URL -o void.tar.xz

		msg "Verifying integrity ..."
		echo "$(grep $ROOTFS_FILENAME sums.txt | cut -d' ' -f4) void.tar.xz" | sha256sum -c
		[[ $? -gt 0 ]] && die "Integrity verification failed! Aborting."
		msg "Integrity verification succeeded!"
		rm sums.txt
	fi

	msg "Decompressing rootfs ..."
	tar -xf void.tar.xz -C $TARGET_DIR
fi

msg "Mounting pseudo filesystems ..."
mountpoint -q $TARGET_DIR/proc || mount -t proc proc $TARGET_DIR/proc
mountpoint -q $TARGET_DIR/sys || mount -t sysfs sys $TARGET_DIR/sys
mountpoint -q $TARGET_DIR/dev || mount --rbind /dev $TARGET_DIR/dev
mountpoint -q $TARGET_DIR/run || mount --rbind /run $TARGET_DIR/run

msg "Copying /etc/resolv.conf to rootfs ..."
cp /etc/resolv.conf $TARGET_DIR/etc

msg "Copying configuration files to rootfs ..."
install -m600 conf.d/doas.conf $TARGET_DIR/etc
install -D conf.d/sv_autologin $TARGET_DIR/etc/sv/autologin/run
install -o joe -g joe -m644 -D -t $TARGET_DIR/home/joe conf.d/countryside.jpg

msg "Copying functions and variables to temporary file ..."
cp ./env $TARGET_DIR/env.tmp

msg "Entering chroot ..."
chroot $TARGET_DIR /bin/bash << "EOF"
# Starting from here, all commands are run inside the chroot

. /env.tmp

msg "Removing temporary file ..."
rm /env.tmp

msg "Updating xbps ..."
xbps-install -Suy xbps

msg "Removing unnecessary packages ..."
xbps-remove -y base-container-full
xbps-remove -y ${packages_remove[@]}

# Most packages are wrongly marked as orphans now. To fix those, find out which
# packages are not required by other packages and mark them as explicitly installed.
msg "Fixing orphans ..."
for i in $(xbps-query -O); do
	echo "$i $(xbps-query -X $i | wc -l)"
done | awk '$2 == "0" { print $1 }' | xargs xbps-pkgdb -m manual

msg "Updating all packages ..."
xbps-install -uy

msg "Installing additional packages ..."
xbps-install -y ${packages_install[@]}

msg "Setting hostname ..."
echo $hostname > /etc/hostname

msg "Setting locale to C.UTF-8 ..."
echo "LANG=C.UTF-8" > /etc/locale.conf
sed -Ei -e 's/^#(C.UTF-8)/\1/' -e 's/^(en_US.UTF-8)/#\1/' /etc/default/libc-locales
xbps-reconfigure -f glibc-locales

msg "Setting password for root ..."
echo 'root:xyz123' | chpasswd -c SHA512
msg "Changing login shell of root ..."
chsh -s /bin/bash root
msg "Creating user joe ..."
useradd -m joe
usermod -aG wheel joe
msg "Setting password for joe ..."
echo 'joe:xyz123' | chpasswd -c SHA512

msg "Enabling services ..."
for service in dhcpcd elogind dbus; do
	ln -s /etc/sv/$service /etc/runit/runsvdir/default
done

msg "Reconfiguring all packages ..."
xbps-reconfigure -fa

EOF

msg "Exiting chroot, unmounting all filesystems ..."
umount -R $TARGET_DIR/proc
umount -R $TARGET_DIR/sys
umount -R $TARGET_DIR/dev
umount -R $TARGET_DIR/run
