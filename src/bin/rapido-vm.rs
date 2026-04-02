// SPDX-License-Identifier: (GPL-2.0 OR GPL-3.0)
// Copyright (C) 2025 SUSE LLC
use std::collections::HashMap;
use std::fs;
use std::hash::{DefaultHasher, Hasher};
use std::io::{self, BufRead};
use std::os::unix::fs::FileTypeExt;
use std::path;
use std::process;
use std::str;

use rapido::host_kernel_vers;

fn vm_is_running(vm_pid_file: &str) -> io::Result<bool> {
    let mut pid = String::new();
    let n = match fs::File::open(vm_pid_file) {
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(false),
        Err(e) => return Err(e),
        Ok(f) => io::BufReader::new(f).read_line(&mut pid)?,
    };

    let pid = pid.trim_end();
    if n < 1 || n > 16 || usize::from_str_radix(pid, 10).is_err() {
        eprintln!("bad qemu pid file data ({} bytes): {}", n, pid);
        return Err(io::Error::from(io::ErrorKind::InvalidInput));
    }

    return match fs::symlink_metadata(&format!("/proc/{}", pid)) {
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(false),
        Err(e) => return Err(e),
        Ok(_) => Ok(true),
    };
}

// Generate a reproducible MAC address based on vm_num and vm_tap IDs.
// We can reuse the generic hashmap hash lib for this \o/
fn vm_mac_gen(vm_num: u64, vm_tap: &str) -> String {
    let mut hasher = DefaultHasher::new();
    hasher.write_u64(vm_num);
    hasher.write(vm_tap.as_bytes());
    let h: u64 = hasher.finish();
    format!("b8:{:02x}:{:02x}:{:02x}:{:02x}:{:02x}",
        h & 0xff, (h >> 8) & 0xff, (h >> 16) & 0xff, (h >> 24) & 0xff,
        (h >> 32) & 0xff)
}

struct VmResources {
    cpus: u32,
    mem: String,
    net: bool,
}

// Process a cpio path. @VmResources is updated for any corresponding rapido-rsc
// path. Any path under rapido-rsc returns true (inc. parent), otherwise false.
// XXX these paths assume leading '/' are stripped, which cpio.rs does before
// writing cpio entries. Dracut also lacks leading '/' due to its staging area.
fn vm_resource_line_process(line: &[u8], rscs: &mut VmResources) -> io::Result<bool> {
    match line {
        // vim compiled from string via: s/\(.\)/b'\1', /g
        // rapido-rsc/cpu/
        [b'r', b'a', b'p', b'i', b'd', b'o', b'-', b'r', b's', b'c', b'/',
         b'c', b'p', b'u', b'/', val @ ..] => {
            rscs.cpus = match str::from_utf8(val) {
                Ok(s) => match s.parse::<u32>() {
                    Err(_) => Err(io::Error::from(io::ErrorKind::InvalidData)),
                    Ok(sp) => Ok(sp),
                },
                Err(_) => Err(io::Error::from(io::ErrorKind::InvalidData)),
            }?;
        }
        // rapido-rsc/mem/
        [b'r', b'a', b'p', b'i', b'd', b'o', b'-', b'r', b's', b'c', b'/',
         b'm', b'e', b'm', b'/', val @ ..] => {
            rscs.mem = match str::from_utf8(val) {
                Err(_) => Err(io::Error::from(io::ErrorKind::InvalidData)),
                Ok(s) => {
                    match s.rsplit_once(['m', 'M', 'g', 'G']) {
                        None if s.parse::<u64>().is_ok() => Ok(s.to_string()),
                        Some((n, u)) if n.parse::<u64>().is_ok() && u == "" => {
                            Ok(s.to_string())
                        },
                        None | Some((_, _)) => {
                            Err(io::Error::from(io::ErrorKind::InvalidData))
                        },
                    }
                },
            }?;
        },
        // rapido-rsc/qemu/custom_args
        [b'r', b'a', b'p', b'i', b'd', b'o', b'-', b'r', b's', b'c', b'/',
         b'q', b'e', b'm', b'u', b'/',
         b'c', b'u', b's', b't', b'o', b'm', b'_', b'a', b'r', b'g', b's'] => {
            // obsolete way for images to inject their own qemu params.
            // cut scripts should instead assert that the args required are set.
            eprintln!("ignoring qemu custom_args presence");
        },
        // rapido-rsc/net
        [b'r', b'a', b'p', b'i', b'd', b'o', b'-', b'r', b's', b'c', b'/',
         b'n', b'e', b't'] => {
            rscs.net = true;
        },
        // catch any unprocessed rapido-rsc path, so we return true.
        [b'r', b'a', b'p', b'i', b'd', b'o', b'-', b'r', b's', b'c', .. ] => {},
        // not a rapido-rsc path.
        _ => return Ok(false),
    }

    // got a valid rapido-rsc path or parent directory
    Ok(true)
}

fn vm_resources_get(initramfs_img: &str) -> io::Result<VmResources> {
    // rapido defaults
    let mut rscs = VmResources{
        cpus: 2,
        mem: "512M".to_string(),
        net: false,
    };

    let f = fs::OpenOptions::new().read(true).open(&initramfs_img)?;
    // BufReader I/O is ugly for archive_walk: read(8k) + seek(next_hdr_off)
    // next_hdr_off is negative unless file len > 8k - (HDR_LEN + namesize)
    let reader = io::BufReader::new(f);
    let mut archive_walker = cpio::archive_walk(reader)?;
    let mut in_rapido_rsc_path = false;
    while let Some(archive_ent) = archive_walker.next() {
        let ent = match archive_ent {
            Err(e) => {
                eprintln!("archive traversal failed");
                return Err(e);
            },
            Ok(ent) => ent,
        };

        match vm_resource_line_process(
            // namesize includes nul. cpio ensures 0< namesize < PATH_MAX+1
            &ent.name[0 .. (ent.namesize as usize) - 1],
            &mut rscs
        )? {
            true => in_rapido_rsc_path = true,
            // optimization: break loop when leaving rapido-rsc/ paths.
            // rsc entries must be placed together in the archive and can be
            // placed at the start to minimise traversal.
            false if in_rapido_rsc_path => break,
            false => {},
        }
    }

    Ok(rscs)
}

struct QemuArgs<'a>  {
    qemu_bin: &'a str,
    kernel_img: String,
    console: &'a str,
    params: Vec<&'a str>,
}

fn vm_qemu_args_get(conf: &HashMap<String, String>) -> io::Result<QemuArgs> {
    let mut params = vec!();
    let mut qemu_args: Option<QemuArgs> = None;

    //let (kconfig: String, krel: Option<&str>) = match conf.get("KERNEL_SRC") {
    let (kconfig, krel) = match conf.get("KERNEL_SRC") {
        Some(ks) if !ks.is_empty() => (format!("{ks}/.config"), None),
        None | Some(_) => match conf.get("KERNEL_RELEASE") {
            Some(rel) => (format!("/boot/config-{rel}"), Some(rel.clone())),
            None => {
                let rel = host_kernel_vers()?;
                (format!("/boot/config-{rel}"), Some(rel.to_string()))
            },
        },
    };

    match fs::symlink_metadata("/dev/kvm") {
        Ok(md) if md.file_type().is_char_device() => {
            params.extend(["-machine", "accel=kvm"])
        },
        Err(_) | Ok(_) => {},
    };

    let ksrc = conf.get("KERNEL_SRC");

    let f = fs::OpenOptions::new().read(true).open(&kconfig)?;
    for line in io::BufReader::new(f).lines().map_while(Result::ok) {
        if line == "CONFIG_X86_64=y" {
            qemu_args = Some(QemuArgs{
                kernel_img: match ksrc {
                    Some(ks) if !ks.is_empty() => format!("{ks}/arch/x86/boot/bzImage"),
                    // krel always set without KERNEL_SRC
                    None | Some(_) => format!("/boot/vmlinuz-{}", krel.unwrap()),
                },
                qemu_bin: "qemu-system-x86_64",
                console: "ttyS0",
                params,
            });
            break;
        } else if line == "CONFIG_ARM64=y" {
            params.extend([
                "-machine", "virt,gic-version=host",
                "-cpu", "host"
            ]);
            qemu_args = Some(QemuArgs{
                kernel_img: match ksrc {
                    Some(ks) => format!("{ks}/arch/arm64/boot/Image"),
                    None => format!("/boot/Image-{}", krel.unwrap()),
                },
                qemu_bin: "qemu-system-aarch64",
                console: "ttyAMA0",
                params,
            });
            break;
	} else if line == "CONFIG_PPC64=y" {
            qemu_args = Some(QemuArgs{
                kernel_img: match ksrc {
                    Some(ks) => format!("{ks}/arch/powerpc/boot/zImage"),
                    None => format!("/boot/vmlinux-{}", krel.unwrap()),
                },
                qemu_bin: "qemu-system-ppc64",
                console: "hvc0",
                params,
            });
            break;
	} else if line == "CONFIG_S390=y" {
            qemu_args = Some(QemuArgs{
                kernel_img: match ksrc {
                    Some(ks) => format!("{ks}/arch/s390/boot/bzImage"),
                    None => format!("/boot/bzImage-{}", krel.unwrap()),
                },
                qemu_bin: "qemu-system-s390x",
                console: "ttysclp0",
                params,
            });
            break;
        }
    }

    if qemu_args.is_none() {
        eprintln!("architecture not yet supported, please add it");
        return Err(io::Error::from(io::ErrorKind::Unsupported));
    }

    let qemu_args = qemu_args.unwrap();
    if fs::symlink_metadata(&qemu_args.kernel_img).is_err() {
        eprintln!(
            "no kernel image present at {}, wrong detection or build needed",
            qemu_args.kernel_img
        );
        return Err(io::Error::from(io::ErrorKind::NotFound));
    }

    return Ok(qemu_args);
}

// TODO: call TIOCGWINSZ ioctl directly?
fn host_stty_size(kcmdline: &mut String, kparam: &'static str) -> Option<()> {
    let out = match process::Command::new("stty")
        .args(&["size"])
        .stdout(process::Stdio::piped())
        .spawn() {
        Err(_) => return None,
        Ok(p) => match p.wait_with_output() {
            Err(_) => return None,
            Ok(o) if !o.status.success() => return None,
            Ok(o) => o.stdout,
        }
    };

    let mut iter = out.split(|c| !matches!(*c, b'0'..=b'9'));
    let rows = iter.next()?;
    let cols = iter.next()?;
    if rows.len() < 1 || cols.len() < 1 {
        eprintln!("bogus stty output {:?} {:?}", rows, cols);
        return None;
    }

    kcmdline.push_str(kparam);
    for c in rows {
        kcmdline.push(char::from(*c));
    }
    kcmdline.push(',');
    for c in cols {
        kcmdline.push(char::from(*c));
    }
    Some(())
}

fn vm_start(vm_num: u64, vm_pid_file: &str, initramfs_img: &str, conf: &HashMap<String,String>) -> io::Result<()> {
    let mut qemu_args = vm_qemu_args_get(conf)?;
    // systemd (incl. networkd) needs a 32-char hex ID for dhcp leases, etc.
    let mut kcmdline = format!(
        "rdinit=/rdinit console={} rapido.vm_num={} systemd.machine_id={:032x}",
        qemu_args.console,
        vm_num,
        vm_num
    );
    host_stty_size(&mut kcmdline, " rapido.stty=");
    let net_conf_dir = format!(
        "{}/vm{}",
        conf.get("VM_NET_CONF").expect("VM_NET_CONF not set"),
        vm_num
    );

    match fs::read_to_string(format!("{net_conf_dir}/hostname")) {
        Err(e) if e.kind() == io::ErrorKind::NotFound => {},
        Err(e) => return Err(e),
        Ok(hn) => {
            kcmdline.push_str(&format!(" rapido.hostname={}", hn.trim_end()));
        },
    }

    let rscs = match vm_resources_get(&initramfs_img) {
        Err(e) if e.kind() == io::ErrorKind::NotFound => {
            eprintln!("no initramfs image at {initramfs_img}. Run \"cut_X\" script?");
            return Err(e);
        },
        Err(e) => return Err(e),
        Ok(r) => r,
    };

    let cpus = format!("{},sockets={},cores=1,threads=1", rscs.cpus, rscs.cpus);
    qemu_args.params.extend([
        "-smp", &cpus,
        "-m", &rscs.mem,
        "-kernel", &qemu_args.kernel_img,
        "-initrd", initramfs_img,
        "-pidfile", vm_pid_file,
    ]);

    // params is Vec<&str>, so stash generated net Strings elsewhere
    let mut net_params_stash: Vec<String> = vec!();

    if !rscs.net {
        qemu_args.params.extend(["-net", "none"]);
    } else {
        kcmdline.push_str(" net.ifnames=0");

        let mut i = 0;
	for entry in fs::read_dir(&net_conf_dir)? {
            let entry = entry?;
            let path = entry.path();
            match path.extension() {
                None => continue,
                Some(e) if e.as_encoded_bytes() != b"network" => continue,
                Some(_) => {},
            }
            let vm_tap = match path.file_stem() {
                None => continue,
                Some(t) => match t.to_str() {
                    None => continue,
                    Some(t_str) => t_str,
                },
            };
            // Only attempt to add host IFF_TAP (0x02) devices as
            // qemu netdevs. This allows for extra VM virtual device
            // creation and configuration via net-conf.
            const IFF_TAP: usize = 0x02;
            let mut tp = path::PathBuf::from("/sys/class/net/");
            tp.push(vm_tap);
            tp.push("tun_flags");
            let tun_flags = match fs::read(&tp) {
                Err(_) => continue,
                Ok(flags) => match str::from_utf8(&flags) {
                    Err(_) => continue,
                    Ok(flags_str) => {
                        if let Some(s) = flags_str.strip_prefix("0x") {
                            usize::from_str_radix(s.trim_end(), 16)
                        } else {
                            eprintln!("{:?} missing expected 0x flags prefix", tp);
                            return Err(io::Error::from(io::ErrorKind::InvalidData));
                        }
                    },
                },
            };
            match tun_flags {
                Err(_) => {
                    eprintln!("unexpected tun_flags at {:?}", tp);
                    return Err(io::Error::from(io::ErrorKind::InvalidData));
                },
                Ok(flags_val) if flags_val & IFF_TAP != IFF_TAP => continue,
                Ok(_) => {},
            }

            let tap_mac = vm_mac_gen(vm_num, vm_tap);

            // TODO append net conf MAC [match] to cpio, instead of at boot
            // time via kcmdline.
            kcmdline.push_str(&format!(" rapido.mac.{vm_tap}={tap_mac}"));

            net_params_stash.extend([
              "-device".to_string(),
              format!("virtio-net,netdev=if{i},mac={tap_mac}"),
              "-netdev".to_string(),
              format!("tap,id=if{i},script=no,downscript=no,ifname={vm_tap}"),
            ]);
            i += 1;
        }
        if i == 0 {
            eprintln!("no valid TAP devices found in {net_conf_dir}");
        }
    }

    if let Some(kp) = conf.get("QEMU_EXTRA_KERNEL_PARAMS") {
        kcmdline.push_str(&format!(" {kp}"));
    }

    qemu_args.params.extend(["-append", &kcmdline]);

    let virtfs_sp: String;
    if let Some(vsp) = conf.get("VIRTFS_SHARE_PATH") {
        virtfs_sp = format!("local,path={vsp},mount_tag=host0,security_model=mapped,id=host0");
        qemu_args.params.extend(["-virtfs", &virtfs_sp]);
    }

    if let Some(qea) = conf.get("QEMU_EXTRA_ARGS") {
        qemu_args.params.extend(qea.split(&[' ', '\n']));
    }

    let mut spawned_vm = process::Command::new(qemu_args.qemu_bin)
        .args(qemu_args.params)
        .args(net_params_stash)
        .spawn()
        .expect("failed to execute qemu");
    match spawned_vm.wait() {
        Err(e) => {
            // TODO stdout / stderr lost here?
            eprintln!("{} failed: {:?}", qemu_args.qemu_bin, e);
            Err(io::Error::from(io::ErrorKind::BrokenPipe))
        },
        Ok(status) if !status.success() => {
            eprintln!("{} exited with status: {}", qemu_args.qemu_bin, status);
            Ok(())
        },
        Ok(_) => Ok(()),
    }
}

fn main() -> io::Result<()> {
    let conf = match rapido::host_rapido_conf_open(rapido::RAPIDO_CONF_PATH) {
        Err(e) if e.kind() == io::ErrorKind::NotFound => {
            rapido::conf_defaults()
        },
        Err(e) => return Err(e),
        Ok((f, p)) => {
            let mut conf = rapido::conf_defaults();
            if let Err(e) = kv_conf::kv_conf_process_append(
                io::BufReader::new(f),
                &mut conf
            ) {
                eprintln!("failed to process {:?}: {:?}", p, e);
                return Err(e);
            }
            conf
        },
    };
    // unwrap: both keys have defaults set
    let pid_dir = conf.get("QEMU_PID_DIR").unwrap();
    let initramfs_img = conf.get("DRACUT_OUT").unwrap();

    // 1k rapido VM limit is arbitrary
    for vm_num in 1..1000 {
        let vm_pid_file = format!("{}/rapido_vm{}.pid", pid_dir, vm_num);
        if !vm_is_running(&vm_pid_file)? {
            return vm_start(vm_num, &vm_pid_file, &initramfs_img, &conf);
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vm_resources_parse() {
        let line = b"rapido-rsc/cpu/5";
        let mut rscs = VmResources{
            cpus: 0,
            mem: String::new(),
            net: false,
        };
        assert_eq!(vm_resource_line_process(line, &mut rscs).unwrap(), true);
        assert_eq!(rscs.cpus, 5);

        let line = b"rapido-rsc/mem/5G";
        assert_eq!(vm_resource_line_process(line, &mut rscs).unwrap(), true);
        assert_eq!(rscs.mem, "5G");

        let line = b"rapido-rsc/mem/5m";
        assert_eq!(vm_resource_line_process(line, &mut rscs).unwrap(), true);
        assert_eq!(rscs.mem, "5m");

        let line = b"rapido-rsc/mem/5t";
        assert!(vm_resource_line_process(line, &mut rscs).is_err());

        let line = b"rapido-rsc/net";
        assert_eq!(vm_resource_line_process(line, &mut rscs).unwrap(), true);
        assert_eq!(rscs.net, true);

        let line = b"not/a/root/rapido-rsc/path";
        assert_eq!(vm_resource_line_process(line, &mut rscs).unwrap(), false);

        let line = b"rapido-rsc/mem/5GG";
        assert!(vm_resource_line_process(line, &mut rscs).is_err());

        let line = b"rapido-rsc/mem/5mG";
        assert!(vm_resource_line_process(line, &mut rscs).is_err());
    }
}
