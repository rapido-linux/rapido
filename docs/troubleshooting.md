# Troubleshooting

### QEMU loops in SeaBIOS during boot

When building kernels with a linker from binutils version 2.31 or later, commit
e3d03598e8ae7 ("x86/build/64: Force the linker to use 2MB page size") from
mainline (v4.16-rc7) is required for proper alignment.
