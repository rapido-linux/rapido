This is an example config file for passthrough network device driver testing.


All these variables would likely need to be set according to the developer environment.


    #
    # Path to Linux kernel source. Prior to running "rapido cut", the kernel
    # should be built, with modules installed (see KERNEL_INSTALL_MOD_PATH below).
    # e.g. KERNEL_SRC="/home/me/linux"
    #KERNEL_SRC=""

    # Path to compiled kernel modules.
    # If left blank, Dracut will use its default (e.g. /lib/modules) search path.
    # A value of "${KERNEL_SRC}/mods" makes sense when used alongside
    # "INSTALL_MOD_PATH=./mods make modules_install" during kernel compilation.
    # e.g. KERNEL_INSTALL_MOD_PATH="${KERNEL_SRC}/mods"
    #KERNEL_INSTALL_MOD_PATH=""

    # The name of the kernel module under test.
    # Passed to the VM as a kernel parameter for use in the test suite.
    # e.g. NET_TEST_KMOD="tn40xx"
    #NET_TEST_KMOD=""

    # The location of the test suite to add into the VM.
    # e.g. NET_TEST_SUITE="/home/me/tn40xx-driver/test"
    #NET_TEST_SUITE=""

    # The host PCI address of the network peripheral for the driver under test.
    # This device must use the vfio-pci stub driver in the host, to be passed to
    # the VM.
    # e.g. NET_TEST_DEV_HOST="07:00.0"
    #NET_TEST_DEV_HOST=""

    # The PCI address of the peripheral in the VM.
    # Passed to the VM as a kernel parameter and used in the test suite to identify
    # the peripheral for the driver under test.
    # e.g. NET_TEST_DEV_VM="0000:00:03.0"
    #NET_TEST_DEV_VM=""

    # Enable IOMMU and pass the PCIe network peripheral into the VM.
    # e.g.
    # QEMU_EXTRA_ARGS="\
    #  -M q35,accel=kvm,kernel-irqchip=split \
    #  -cpu host \
    #  -nographic\
    #  -device intel-iommu,intremap=on,caching-mode=on,device-iotlb=on \
    #  -device virtio-rng-pci \
    #  -device vfio-pci,host=$NET_TEST_DEV_HOST \
    # "
    #QEMU_EXTRA_ARGS=""

