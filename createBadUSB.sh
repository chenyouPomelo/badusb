#!/bin/bash
#set -x
#set -e

echo "-------------------------------"
echo "preparing badusb for usb-armory"
echo "------by Daniel Wolfmayr-------"
echo "-------------------------------"

#Pre-requisites
sudo apt-get install parted debootstrap binfmt-support qemu-user-static u-boot-tools wget git xz-utils tar build-essential bc
sudo apt-get install lib32z1 lib32ncurses5 # on Ubuntu 12.04 install ia32-libs instead

sudo apt-get install gcc-arm-linux-gnueabihf
export CROSS_COMPILE=arm-linux-gnueabihf-

echo "-------------------------------"
echo "preparing SDcard...."
echo "-------------------------------"

sudo ls /dev/
echo "Devicename SD-Card: "
read Device

export TARGET_DEV=/dev/$Device     # pick the appropriate device name for your microSD card (e.g. /dev/sdb)
export TARGET_MNT=/mnt         # set the microSD root file system mounting path

sudo umount ${TARGET_DEV}1
sudo umount ${TARGET_DEV}

sudo parted $TARGET_DEV --script mklabel msdos
sudo parted $TARGET_DEV --script mkpart primary ext4 5M 100%
sudo mkfs.ext4 ${TARGET_DEV}1
sudo mount ${TARGET_DEV}1 $TARGET_MNT


#Debian 8
echo "-------------------------------"
echo "downloading and installing Debian 8"
echo "-------------------------------"

sudo qemu-debootstrap --arch=armhf --include=ssh,sudo,ntpdate,fake-hwclock,openssl,vim,nano,cryptsetup,lvm2,locales,less,cpufrequtils,isc-dhcp-server,haveged,whois,iw,wpasupplicant,dbus jessie $TARGET_MNT http://ftp.debian.org/debian/

sudo cp debian8/rc.local ${TARGET_MNT}/etc/rc.local
sudo cp debian8/sources.list ${TARGET_MNT}/etc/apt/sources.list
sudo cp debian8/dhcpd.conf ${TARGET_MNT}/etc/dhcp/dhcpd.conf

sudo sed -i -e 's/INTERFACES=""/INTERFACES="usb0"/' ${TARGET_MNT}/etc/default/isc-dhcp-server
echo "tmpfs /tmp tmpfs defaults 0 0" | sudo tee ${TARGET_MNT}/etc/fstab
echo -e "\nUseDNS no" | sudo tee -a ${TARGET_MNT}/etc/ssh/sshd_config
echo "nameserver 8.8.8.8" | sudo tee ${TARGET_MNT}/etc/resolv.conf
sudo chroot $TARGET_MNT systemctl mask getty-static.service
sudo chroot $TARGET_MNT systemctl mask isc-dhcp-server.service
sudo chroot $TARGET_MNT systemctl mask display-manager.service
sudo chroot $TARGET_MNT systemctl mask hwclock-save.service

sudo chroot $TARGET_MNT apt-get -y update
sudo chroot $TARGET_MNT apt-get install -y ntp
sudo chroot $TARGET_MNT apt-get install -y libssl-dev
sudo chroot $TARGET_MNT apt-get install -y libevent-dev


#finalize & pwd
echo "-------------------------------"
echo "finalize & pwd"
echo "-------------------------------"

echo "ledtrig_heartbeat" | sudo tee -a ${TARGET_MNT}/etc/modules
echo "ci_hdrc_imx" | sudo tee -a ${TARGET_MNT}/etc/modules

#echo "g_multi" | sudo tee -a ${TARGET_MNT}/etc/modules
#echo "options g_multi file=/root/backing_file dev_addr=1a:55:89:a2:69:41 host_addr=1a:55:89:a2:69:42" | sudo tee -a ${TARGET_MNT}/etc/modprobe.d/usbarmory.conf

echo "g_ether" | sudo tee -a ${TARGET_MNT}/etc/modules
echo "options g_ether use_eem=0 dev_addr=1a:55:89:a2:69:41 host_addr=1a:55:89:a2:69:42" | sudo tee -a ${TARGET_MNT}/etc/modprobe.d/usbarmory.conf

#network configuration
echo -e 'allow-hotplug usb0\niface usb0 inet static\n  address 10.0.0.1\n  netmask 255.255.255.0\n  gateway 10.0.0.2'| sudo tee -a ${TARGET_MNT}/etc/network/interfaces
echo "usbarmory" | sudo tee ${TARGET_MNT}/etc/hostname
echo "usbarmory  ALL=(ALL) NOPASSWD: ALL" | sudo tee -a ${TARGET_MNT}/etc/sudoers
echo -e "127.0.1.1\tusbarmory" | sudo tee -a ${TARGET_MNT}/etc/hosts

#serial configuration
echo "start on stopped rc or RUNLEVEL=[12345]
stop on runlevel [!12345]

respawn
exec /sbin/getty -l 115200 ttyGS0 vt102
" | sudo tee -a ${TARGET_MNT}/etc/init/ttyGS0.conf

#mass storage configuration
#sudo dd bs=1M count=64 if=/dev/zero of=${TARGET_MNT}/root/backing_file

#sudo parted ${TARGET_MNT}/root/backing_file --script mktable msdos
#sudo parted ${TARGET_MNT}/root/backing_file --script mkpart primary fat32 1 100%

#offset in backing file in bytes for -o option
#LOOPER_DEV=`sudo losetup -f`
#sudo losetup -o 1048576 ${LOOPER_DEV} ${TARGET_MNT}/root/backing_file
#sudo mkfs.vfat -F 32 ${LOOPER_DEV}
#sudo losetup -d ${LOOPER_DEV}


#create user (usbarmory:usbarmory)
sudo chroot $TARGET_MNT /usr/sbin/useradd -s /bin/bash -p `mkpasswd -m sha-512 usbarmory` -m usbarmory

cp -avr badusb-scripts/* ${TARGET_MNT}/home/usbarmory
mkdir ${TARGET_MNT}/home/usbarmory/SniffedFiles
mkdir ${TARGET_MNT}/home/usbarmory/SniffedFiles/sslsplit
mkdir ${TARGET_MNT}/home/usbarmory/SniffedFiles/sslsplit/logdir
mkdir ${TARGET_MNT}/home/usbarmory/certificate
cp -avr certificate/* ${TARGET_MNT}/home/usbarmory/certificate

#install sniff-applications
echo "-------------------------------"
echo "Install sniff-applications"
echo "-------------------------------"

sudo chroot $TARGET_MNT apt-get install -y tcpdump
sudo chroot $TARGET_MNT apt-get install -y mitmproxy

echo "---------------------------------------------------------------------"
sudo rm ${TARGET_MNT}/usr/bin/qemu-arm-static


#Kernel: Linux 4.6.1
echo "-------------------------------"
echo "building Kernel: Linux 4.6.1"
echo "-------------------------------"

cd linux-kernel-files
export ARCH=arm
wget https://www.kernel.org/pub/linux/kernel/v4.x/linux-4.6.1.tar.xz
tar xvf linux-4.6.1.tar.xz && cd linux-4.6.1

make distclean
sudo cp ../usbarmory_linux-4.6.config .config
sudo cp ../imx53-usbarmory-common.dtsi arch/arm/boot/dts/imx53-usbarmory-common.dtsi
sudo cp ../imx53-usbarmory.dts arch/arm/boot/dts/imx53-usbarmory.dts
sudo cp ../imx53-usbarmory-host.dts arch/arm/boot/dts/imx53-usbarmory-host.dts
sudo cp ../imx53-usbarmory-gpio.dts arch/arm/boot/dts/imx53-usbarmory-gpio.dts
sudo cp ../imx53-usbarmory-spi.dts arch/arm/boot/dts/imx53-usbarmory-spi.dts
sudo cp ../imx53-usbarmory-i2c.dts arch/arm/boot/dts/imx53-usbarmory-i2c.dts

make uImage LOADADDR=0x70008000 modules imx53-usbarmory.dtb imx53-usbarmory-host.dtb imx53-usbarmory-gpio.dtb imx53-usbarmory-spi.dtb imx53-usbarmory-i2c.dtb
sudo cp arch/arm/boot/uImage ${TARGET_MNT}/boot/
sudo cp arch/arm/boot/dts/imx53-usbarmory*.dtb ${TARGET_MNT}/boot/
sudo make INSTALL_MOD_PATH=$TARGET_MNT ARCH=arm modules_install
sudo umount $TARGET_MNT

cd ..
cd ..
cd u-boot

#Bootloader: U-Boot 2016.05
echo "-------------------------------"
echo "building Bootloader: U-Boot 2016.05"
echo "-------------------------------"

tar xvf u-boot-2016.05.tar.bz2 && cd u-boot-2016.05

make distclean
make usbarmory_config
make ARCH=arm
sudo dd if=u-boot.imx of=$TARGET_DEV bs=512 seek=2 conv=fsync
