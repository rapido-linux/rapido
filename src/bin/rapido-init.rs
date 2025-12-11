// SPDX-License-Identifier: (GPL-2.0 OR GPL-3.0)
// Copyright (C) 2025 SUSE LLC
use std::io::{self, Write};
use std::ffi::OsString;
use std::fs;
use std::collections::HashMap;
use std::os::unix;
use std::process::Command;
use std::str;

// we expect it in root on VMs
const RAPIDO_CONF: &str = "/rapido.conf";

fn init_mount(do_debugfs: bool, do_virtfs: bool) -> io::Result<()> {
    let mounts = [
        ["-t", "proc", "-o", "nosuid,noexec,nodev", "proc", "/proc"],
        ["-t", "sysfs", "-o", "nosuid,noexec,nodev", "sysfs", "/sys"],
        ["-t", "devtmpfs", "-o", "nosuid,noexec", "devtmpfs", "/dev"],
        ["-t", "devpts", "-o", "nosuid,noexec", "devpts", "/dev/pts"], // needed?
        ["-t", "tmpfs", "-o", "mode=1777,noexec,nosuid,nodev", "tmpfs", "/dev/shm"], // needed?
        ["-t", "tmpfs", "-o", "mode=755,noexec,nosuid,nodev", "tmpfs", "/run"],
        ["-t", "tmpfs", "-o", "noexec,nosuid,nodev", "tmpfs", "/tmp"],
    ];
    // sys_fsmount in the future, when we can do it without dependency bloat?
    for mount_args in mounts {
        fs::create_dir_all(mount_args.last().unwrap())?;
        let status = Command::new("mount")
            .args(&mount_args)
            .status()
            .expect("failed to execute mount command");
        if !status.success() {
            println!("mount failed");
            return Err(io::Error::from(io::ErrorKind::BrokenPipe));
        }
    }

    if do_debugfs {
        let status = Command::new("mount")
            .args(&["-t", "debugfs", "debugfs", "/sys/kernel/debug/"])
            .status()
            .expect("failed to execute mount command");
        if !status.success() {
            println!("debugfs mount failed - ignoring");
        }
    }

    if do_virtfs {
        fs::create_dir_all("/host")?;
        let status = Command::new("mount")
            .args(&["-t", "9p", "host0", "/host"])
            .status()
            .expect("failed to execute mount command");
        if !status.success() {
            println!("9p mount failed - ignoring");
        }
    }

    Ok(())
}

#[derive(PartialEq)]
#[derive(Debug)]
struct KcliArgs<'a> {
    rapido_hostname: Option<&'a str>,
    rapido_vm_num: Option<&'a str>,
    rapido_tap_mac: Option<HashMap<&'a str, &'a str>>,
    systemd_machine_id: Option<&'a str>,
    console: Option<&'a str>,
}

fn kcli_parse(kcmdline: &[u8]) -> io::Result<KcliArgs> {
    let mut args = KcliArgs {
        rapido_hostname: None,
        rapido_vm_num: None,
        rapido_tap_mac: None,
        systemd_machine_id: None,
        console: None,
    };

    // We know exactly what we're looking for, so don't bother with flexible
    // parsing via e.g. kv-conf.
    // It'd be nice if we could construct these match arrays at compile time
    // from the corresponding "key = " strings. For now they're vim compiled
    // via: s/\(.\)/b'\1', /g

    for w in kcmdline.split(|c| matches!(c, b' ')) {
        match w {
            // rapido.hostname
            [b'r', b'a', b'p', b'i', b'd', b'o', b'.',
            b'h', b'o', b's', b't', b'n', b'a', b'm', b'e', b'=', val @ ..] => {
                args.rapido_hostname = match str::from_utf8(val) {
                    Err(_) => {
                        return Err(io::Error::from(io::ErrorKind::InvalidData));
                    },
                    Ok(s) => Some(s),
                };
            },
            // rapido.vm_num
            [b'r', b'a', b'p', b'i', b'd', b'o', b'.',
            b'v', b'm', b'_', b'n', b'u', b'm', b'=', val @ ..] => {
                args.rapido_vm_num = match str::from_utf8(val) {
                    Err(_) => {
                        return Err(io::Error::from(io::ErrorKind::InvalidData));
                    },
                    Ok(s) => Some(s),
                };

            },
            // rapido.mac.<tap>=<mac>
            [b'r', b'a', b'p', b'i', b'd', b'o', b'.',
            b'm', b'a', b'c', b'.', tap_mac_kv @ ..] => {
                let (tap, mac) = match str::from_utf8(tap_mac_kv) {
                    Err(_) => {
                        return Err(io::Error::from(io::ErrorKind::InvalidData));
                    },
                    Ok(s) if !s.contains('=') => {
                        return Err(io::Error::from(io::ErrorKind::InvalidData));
                    },
                    Ok(s) => s.split_once('=').unwrap(),
                };
                let map = match args.rapido_tap_mac {
                    None => HashMap::from([ (tap, mac) ]),
                    Some(mut m) => {
                        m.insert(tap, mac);
                        m
                    },
                };
                args.rapido_tap_mac = Some(map);
            },
            // systemd.machine_id
            [b's', b'y', b's', b't', b'e', b'm', b'd', b'.',
            b'm', b'a', b'c', b'h', b'i', b'n', b'e', b'_', b'i', b'd', b'=',
            val @ ..] => {
                args.systemd_machine_id = match str::from_utf8(val) {
                    Err(_) => {
                        return Err(io::Error::from(io::ErrorKind::InvalidData));
                    },
                    Ok(s) => Some(s),
                };
            },
            // console
            [b'c', b'o', b'n', b's', b'o', b'l', b'e', b'=', val @ ..] => {
                args.console = match str::from_utf8(val) {
                    Err(_) => {
                        return Err(io::Error::from(io::ErrorKind::InvalidData));
                    },
                    Ok(s) => Some(s),
                };
            },
            [ _unused @ .. ] => {},
        };
    }

    Ok(args)
}

// FIXME: if all modules are builtin then rapido-cut won't install modprobe
fn kmods_load(conf: &HashMap<String, String>, has_net: bool) -> io::Result<()> {
    let kmods = rapido::conf_kmod_deps(conf, has_net);

    if kmods.len() > 0 {
        match Command::new("modprobe")
            .env("PATH", "/usr/sbin:/usr/bin:/sbin:/bin")
            .arg("-a")
            .args(&kmods)
            .status() {
            Err(e) => {
                eprintln!("modprobe error: {:?}", e);
                return Err(io::Error::from(io::ErrorKind::BrokenPipe));
            },
            Ok(status) if !status.success() => {
                println!("modprobe failed: {:?}", status);
                return Err(io::Error::from(io::ErrorKind::BrokenPipe));
            },
            Ok(_) => {},
        };
    }

    Ok(())
}

fn init_hostname(kcli_args: &KcliArgs) -> io::Result<String> {
    let hostname: String = match kcli_args.rapido_hostname {
        None => {
            let mut h = String::from("rapido");
            h.push_str(kcli_args.rapido_vm_num.unwrap());
            h
        },
        Some(hd) => {
            match hd.split_once('.') {
                Some((h, d)) => {
                    fs::write("/proc/sys/kernel/domainname", d)?;
                    h.to_string()
                },
                None => hd.to_string(),
            }
        },
    };

    fs::write("/proc/sys/kernel/hostname", &hostname)?;
    // don't set_env(HOSTNAME), pass it to new processes via Command::env

    Ok(hostname)
}

fn init_network(kcli_args: &KcliArgs) -> io::Result<()> {
    // TODO: add dirs to cpio
    fs::create_dir_all("/run/systemd/")?;
    fs::create_dir_all("/etc/systemd/")?;

    let mut vm_netdir = String::from("/rapido-rsc/net/vm");
    vm_netdir.push_str(kcli_args.rapido_vm_num.unwrap());
    unix::fs::symlink(&vm_netdir, "/etc/systemd/network")?;

    match &kcli_args.rapido_tap_mac {
        Some(map) => for (tap, mac) in map {
            let mut f = match fs::OpenOptions::new()
                .write(true)
                .append(true)
                .create(false)
                .open(format!("{}/{}.network", vm_netdir, tap)) {
                    Err(_) => continue,
                    Ok(f) => f,
            };

            write!(f, "\n[Match]\nMACAddress={}", mac)?;
        },
        None => {},
    }

    let mut f = fs::OpenOptions::new()
        .write(true)
        .append(true)
        .create(true)
        .open("/etc/systemd/network/lo.network")?;
    write!(f, "[Match]\nName=lo")?;

    match kcli_args.systemd_machine_id {
        None => {
            eprintln!("systemd.machine_id missing from kcli");
            Err(io::Error::from(io::ErrorKind::InvalidInput))
        },
        Some(mid) => fs::write("/etc/machine-id", mid),
    }?;

    let status = Command::new("/usr/lib/systemd/systemd-udevd")
        .args(&["--daemon"])
        .status()
        .expect("failed to execute systemd-udevd");
    if !status.success() {
        eprintln!("systemd-udevd failed to start");
        return Err(io::Error::from(io::ErrorKind::BrokenPipe));
    }

    let mut entries = fs::read_dir("/sys/class/net/")?
        .map(|res| res.map(|e| e.path().into_os_string()))
        .collect::<Result<Vec<_>, io::Error>>()?;

    let mut udevadm_args = vec!(OsString::from("trigger"));
    udevadm_args.append(&mut entries);
    let status = Command::new("udevadm")
        .args(udevadm_args)
        .status()
        .expect("failed to execute udevadm");
    if !status.success() {
        eprintln!("udevadm failed");
        return Err(io::Error::from(io::ErrorKind::BrokenPipe));
    }

    let mut f = fs::OpenOptions::new()
        .write(true)
        .append(true)
        .create(true)
        .open("/etc/passwd")?;
    write!(
        f,
        "systemd-network:x:482:482:systemd Network Management:/:/sbin/nologin\n"
    )?;

    let status = Command::new("setsid")
        .args(&["--fork", "/usr/lib/systemd/systemd-networkd"])
        .status()
        .expect("failed to execute systemd-networkd via setsid");
    if !status.success() {
        eprintln!("systemd-networkd failed to start");
        return Err(io::Error::from(io::ErrorKind::BrokenPipe));
    }

    println!("Waiting for network to come online...");
    let status = Command::new("/usr/lib/systemd/systemd-networkd-wait-online")
        .args(&["--timeout=20"])
        .status()
        .expect("failed to execute systemd-networkd-wait-online");
    if !status.success() {
        eprintln!("systemd-networkd-wait-online failed");
        return Err(io::Error::from(io::ErrorKind::BrokenPipe));
    }

    Ok(())
}

fn init_shell(hostname: String) -> io::Result<()> {
    // rapido.rc starts subsequent autorun scripts
    // TODO future: allow for starting binary autorun payloads instead
    let mut spawned = Command::new("setsid")
        .args(&["--ctty", "--", "bash", "--rcfile", "/rapido.rc", "-i"])
        .envs([
            // RAPIDO_INIT indicates this (non-Dracut) init to vm_autorun, etc.
            ("RAPIDO_INIT", "0.1"),
            ("PATH", "/usr/sbin:/usr/bin:/sbin:/bin:."),
            ("TERM", "linux"),
            ("HOSTNAME", &hostname),
            ("PS1", format!("{}:${{PWD}}# ", hostname).as_str())
        ])
        .spawn()
        .expect("failed to execute bash via setsid");
    match spawned.wait() {
        Err(e) => {
            eprintln!("bash error {:?}", e);
            return Err(io::Error::from(io::ErrorKind::BrokenPipe));
        },
        Ok(status) if status.success() => {},
        Ok(status) => eprintln!("bash ended with status {}", status),
    }
    Ok(())
}

fn init_shutdown() -> io::Result<()> {
    fs::write("/proc/sys/kernel/sysrq", "1\n")?;
    fs::write("/proc/sysrq-trigger", "o\n")?;
    std::thread::sleep(std::time::Duration::from_secs(20));
    Ok(())
}

fn init_main() -> io::Result<()> {
    eprintln!("Starting rapido-init...");

    let f = match fs::File::open(RAPIDO_CONF) {
        Ok(f) => f,
        Err(e) => {
            println!("failed to open {}: {}", RAPIDO_CONF, e);
            return Err(e);
        },
    };
    let mut reader = io::BufReader::new(f);
    let conf = match kv_conf::kv_conf_process(&mut reader) {
        Ok(c) => c,
        Err(e) => {
            println!("failed to process {}: {:?}", RAPIDO_CONF, e);
            return Err(e);
        },
    };

    let has_net = match fs::symlink_metadata("/rapido-rsc/net") {
        Err(_) => false,
        Ok(md) => md.is_dir(),
    };
    let has_dyn_debug = conf.contains_key("DYN_DEBUG_MODULES") || conf.contains_key("DYN_DEBUG_FILES");
    let has_virtfs = conf.contains_key("VIRTFS_SHARE_PATH");

    kmods_load(&conf, has_net)?;

    init_mount(has_dyn_debug, has_virtfs)?;

    let kcmdline = fs::read("/proc/cmdline")?;
    let kcli_args = kcli_parse(&kcmdline)?;

    if kcli_args.rapido_vm_num.is_none() {
        println!("/proc/cmdline missing rapido.vm_num");
        return Err(io::Error::from(io::ErrorKind::InvalidInput));
    }

    let hostname = init_hostname(&kcli_args)?;

    if has_net {
        init_network(&kcli_args)?;
    }

    init_shell(hostname)?;

    Ok(())
}

fn main() -> io::Result<()> {
    match init_main() {
        Err(e) => {
            eprintln!("init failed: {:?}", e);
        },
        Ok(_) => {
            eprintln!("rapido-init completed, shutting down...");
        },
    }

    init_shutdown()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_kcli_parse() {
        let kcli = b"rapido.vm_num=3";
        assert_eq!(
            kcli_parse(kcli).expect("kcli_parse failed"),
            KcliArgs {
                rapido_vm_num: Some("3"),
                rapido_hostname: None,
                rapido_tap_mac: None,
                systemd_machine_id: None,
                console: None,
            }
        );

        let kcli = b"rapido.vm_num=3  rapido.hostname=rapido1 rapido.vm_num=4 console=ttyS0";
        assert_eq!(
            kcli_parse(kcli).expect("kcli_parse failed"),
            KcliArgs {
                rapido_vm_num: Some("4"),
                rapido_hostname: Some("rapido1"),
                rapido_tap_mac: None,
                systemd_machine_id: None,
                console: Some("ttyS0"),
            }
        );

        let kcli = b"rapido.mac.tap1=b8:ac:24:45:c5:01 rapido.mac.tap2=b8:ac:24:45:c5:02";
        assert_eq!(
            kcli_parse(kcli).expect("kcli_parse failed"),
            KcliArgs {
                rapido_vm_num: None,
                rapido_hostname: None,
                rapido_tap_mac: Some(HashMap::from([
                        ("tap1", "b8:ac:24:45:c5:01"),
                        ("tap2", "b8:ac:24:45:c5:02"),
                ])),
                systemd_machine_id: None,
                console: None,
            }
        );
    }
}
