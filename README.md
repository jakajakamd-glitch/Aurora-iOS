# Aurora

Aurora is a normal Theos dynamic-library target written in Objective-C++. It is not a tweak and does not use Logos, `tweak.mk`, a package control file, or a bundle filter.

At load time, Aurora scans dyld’s loaded-image list, compares each image basename case-insensitively with `RobloxLib`, and logs the address of the matching Mach-O image header. Because the requested image has no `.dylib` suffix, the lookup matches the basename `RobloxLib` directly. Aurora polls briefly when RobloxLib is not present at initial load.

The manager call shape is `managers::hook_mgr.func(absolute_address, replacement, backup)`. The current implementation is fail-closed and does not modify executable memory or install a runtime hook. It clears `backup` and returns for invalid input.

The implementation has no intentional public Aurora or manager exports. Build it with:

```sh
export THEOS=/home/ubuntu/theos
cd /home/ubuntu/projects/Aurora
make
```

The verified universal debug artifact is `.theos/obj/debug/Aurora.dylib`, containing armv7, arm64, and arm64e slices.
