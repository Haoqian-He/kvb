#!/bin/bash

vnc=${VNC:-0}
iso_file=${ISO:-""}
no_kernel=${NO_KERNEL:-1}

# QEMU TCP Address and Ports
QEMU_TCP_ADDRESS=127.0.0.1
QEMU_TCP_PORT_SSH=49123
QEMU_TCP_PORT_MONITOR=6873

# Repository information
REPOSITORY_DIR=$(git rev-parse --show-toplevel)
REPOSITORY_NAME=$(basename $REPOSITORY_DIR)

# Drive Files
# WHY???
# 使用feodra 提供内核 qcow2 可以打出来 dmesg 到标准输出
# iso 装的 dmesg 打不到标准输出
QEMU_DRIVE_FILE_FEDORA=/root/data/vm_data/vda.qcow2 # fedora 41 qcow2
VDB_FILE=/root/data/images/vda.qcow2

# QEMU executable
# QEMU_EXEC=$REPOSITORY_DIR/qemu/build/qemu-system-x86_64
QEMU_EXEC=/root/qemu-code/qemu-master/build/qemu-system-x86_64

# Get the correct accelerator
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
	QEMU_ACCEL=kvm
elif [[ "$OSTYPE" == "darwin"* ]]; then
	QEMU_ACCEL=hvf
else
	echo "Unsupported OS"
fi

# QEMU Launch Default
#
# log errors : -d guest_errors -D $REPOSITORY_DIR/errors.log
#

# 给虚拟机共享 host /root
# 需要在虚拟机内挂载 shared folder :
#  mount -t 9p -o trans=virtio hostdir /hostdir
share_path=/root/

extra=""
arg_kernel=""
arg_storage=""
stroage_cnt=0

if [[ $vnc -eq 1 ]]; then
    if [[ -n "$(pidof novnc_proxy)" ]]; then
		kill -9 "$(pidof novnc_proxy)"
	fi
	# qemu VNC 端口是 5900 + offset, 所以 1 就是 5901
	# browser -> novnc 6080 -> qemu vnc 5901
	extra="$extra-vnc :1,password=off "
	/root/qemu-code/noVNC/utils/novnc_proxy --vnc localhost:5901 &
	nonvc_pid=$!
fi

if [[ $iso_file != "" ]]; then
	# -cdrom 会报错
	# qemu-system-x86_64: -boot d -cdrom /root/data/images/Fedora-Server-dvd-x86_64-41-1.4.iso: invalid option
	extra="$extra-cdrom /root/data/images/Fedora-Server-dvd-x86_64-41-1.4.iso "
fi

setup_virtio_blk(){
	filename=$1
	id="drv-blk$stroage_cnt"
	arg_virtio_blk=" -drive file=$filename,format=qcow2,cache=none,aio=native,if=none,discard=unmap,id=$id "
	arg_virtio_blk+=" -device virtio-blk-pci,drive=$id "
	arg_storage+=" $arg_virtio_blk "
	((stroage_cnt+=1))
}

setup_libblk_io() {
	# read-only=off,discard=unmap,cache.direct=on,cache.no-flush=on
	arg_blkio=" -blockdev driver=io_uring,node-name=blkio-iouring,filename=$QEMU_DRIVE_FILE_FEDORA "
	arg_blkio+=" -device virtio-blk-pci,drive=blkio-iouring,serial=blkio-iouring,bootindex=1 "
	arg_storage+=" $arg_blkio"
	((stroage_cnt+=1))
}

setup_kernel() {
	arg_kernel=$(
	cat <<EOF
	-kernel /root/data/images/bzImage -initrd /root/data/images/myinitrd \
	-append "rapido.vm_num=1 rd.systemd.unit=dracut-cmdline.service console=ttyS0"
EOF
        )
}


if [[ $no_kernel -eq 1 ]];then
	setup_virtio_blk $QEMU_DRIVE_FILE_FEDORA
	extra+=" -serial mon:stdio -monitor tcp:$QEMU_TCP_ADDRESS:$QEMU_TCP_PORT_MONITOR,server,nowait > tmp/qemu.log 2>&1 &"
else
	setup_kernel
	extra+=" -serial mon:stdio -nographic"
fi

setup_virtio_blk $VDB_FILE

eval $QEMU_EXEC\
 -machine accel=$QEMU_ACCEL\
 -cpu host\
 $arg_kernel\
 -smp 32\
 -m 32G\
 -display none\
 -device virtio-net,netdev=vmnic\
 -netdev user,id=vmnic,hostfwd=tcp:$QEMU_TCP_ADDRESS:$QEMU_TCP_PORT_SSH-:22\
 -virtfs local,path=$share_path,security_model=mapped,mount_tag=hostdir\
 -fw_cfg name=opt/repositoryname,string=$REPOSITORY_NAME\
 $arg_storage\
 -vnc :1,password=off\
 $extra
 # > tmp/qemu.log 2>&1 &

#alias qemu_fedora_gui="\
# $QEMU_EXEC\
#  -accel $QEMU_ACCEL\
#  -cpu host\
#  -smp 2\
#  -m 3G\
#  -display curses,show-cursor=on\
#  -vga virtio\
#  -device virtio-net,netdev=vmnic\
#  -netdev user,id=vmnic,hostfwd=tcp:$QEMU_TCP_ADDRESS:$QEMU_TCP_PORT_SSH-:22\
#  -drive file=$QEMU_DRIVE_FILE_FEDORA,if=virtio\
#  -virtfs local,path=/workspaces/$REPOSITORY_NAME,security_model=mapped,mount_tag=hostdir\
#  -fw_cfg name=opt/repositoryname,string=$REPOSITORY_NAME\
#  -monitor tcp:$QEMU_TCP_ADDRESS:$QEMU_TCP_PORT_MONITOR,server,nowait"

## Monitor access
#alias qemu_monitor="nc -v $QEMU_TCP_ADDRESS $QEMU_TCP_PORT_MONITOR"
#
## SSH access
#alias fedora="ssh -p $QEMU_TCP_PORT_SSH $QEMU_TCP_ADDRESS"
