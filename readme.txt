Overview
========

Rapido is a utility for rapid testing of Linux kernel changes. It was
initially targeted at Ceph RBD and CephFS kernel client functionality,
but now also covers a number of standalone use cases.

The scripts that make up Rapido are in themselves quite brainless. most
of the heavy lifting is instead performed by:
- Dracut (https://dracut.wiki.kernel.org)
  + Generates a VM image, with kernel-modules and minimal user-space.
- QEMU / KVM (http://qemu.org)
  + Boots a given Dracut VM image and compiled Linux kernel on the local
    system.


Setup
=====

Rapido has a pretty minimal set of dependencies, which should be present
on all major Linux distributions.
- Dracut
- qemu / KVM
- brctl (bridge-utils) and tunctl, used for VM network provisioning

Once all dependencies have been installed, Rapiod can be configured via
rapido.conf. At a minimum, the VM network configuration and Linux kernel
source parameters should be defined, in order to proceed.

The tools/br_setup.sh script should be run as root to configure the
bridge network.
By default, the bridge network is isolated, and isn't connected to any
physical adapters. All parameters (device names, IP addresses, etc.) are
configured in rapido.conf.


Running
=======

Depending on which kernel component or functionality you'd like to test,
choose a "cut_" script to generate a VM image, which pulls all relevant
kernel modules from the rapido.conf KERNEL_SRC directory. The VM
initramfs image will be written to initrds/myinitrd.

Once generated, the VM image and kernel can be booted by running
"vm.sh".


Architecture
============

The "Ceph" configuration and runtime binaries below are only required
if running one of the CephFS or RBD "cut" scripts.

+--------------------+             +------------------------+
|                    |             |                        |
| Ceph configuration |             | Rapido "cut" script    |
| + ceph.conf        +----------+  |                        |
| + keyring          |          |  | +--------------------+ |    +-----+
|                    |          |  | |                    | |    |     |
+--------------------+          |  | | File manifest:     | |    |     |
+------------------------+      |  | | + Kernel modules   | |    |     |
|                        |      v  | | + User-space files | |    |     |
| Ceph runtime           |      |  | |                    | |    |     |
| + Compiled from source |      |  | +---------+----------+ |    |     |
|   + vstart.sh cluster  |      |  |           |            <----+     |
| or                     |      |  | +---------v----------+ |    |     |
| + Local host           |      |  | |                    | |    |     |
|   + Regular Ceph       +------+---->                    | |    |     |
|     cluster            |      |  | |  Dracut initramfs  | |    |  R  |
|                        |      |  | |  generator         | |    |  a  |
+------------------------+      ^  | |                    | |    |  p  |
                                |  | +---------+----------+ |    |  i  |
+-------------------------+     |  |           |            |    |  d  |
|                         |     |  +------------------------+    |  o  |
| Rapido "autorun" script +-----+              |                 |  .  |
|                         |     |    +---------v----------+      |  c  |
+-------------------------+     |    |                    |      |  o  |
                                |    | Initramfs          |      |  n  |
                                ^    | + Includes all     |      |  f  |
+------------------------+      |    |   kernel / user    |      |     |
| Compiled Linux Kernel  |      |    |   dependencies     |      |     |
|                        |      |    |                    |      |     |
| +---------+            |      |    +---------+----------+      |     |
| | Modules +-------------------+              |                 |     |
| +---------+            |         +------------------------+    |     |
|                        |         |           |            |    |     |
| +---------+            |         |  Rapido "vm" script    |    |     |
| | bzImage +-------------------+  |           |            |    |     |
| +---------+            |      |  |  +--------v----+       |    |     |
|                        |      |  |  |             |       <----+     |
+------------------------+      +-----> qemu / KVM  |       |    |     |
                                   |  |             |       |    |     |
                                   |  +--------+----+       |    |     |
                                   |           |            |    +--+--+
                                   +------------------------+       |
   ___________________                         |                    |
   | Virtual network |o-------+    +-----------v--------------+     v
   =========^=========        |    |                          |     |
            |                 |    | Virtual Machine          |     |
            |                 +---o| + Console redirected     |     |
            |                      |   to stdout / from stdin <-----+
+-----------+--------------+       | + autorun script         |     |
|                          |       |   executed on boot       |     |
| Rapido "br_setup" script |       |                          |     v
|                          |       +--------------------------+     |
+-----------^--------------+                                        |
            |                                                       |
            +------------------------------<------------------------+



