// SPDX-License-Identifier: (GPL-2.0 OR GPL-3.0)
// Copyright (C) 2025 SUSE LLC
use std::env;
use std::fs;
use std::io;
use std::collections::HashMap;
use std::path::PathBuf;
use std::str;

// ./rapido.conf default path can be overridden by RAPIDO_CONF env var
pub const RAPIDO_CONF_PATH: &str = "rapido.conf";
// parameters below may be overridden by rapido.conf...
// default VM network config path, also used for tap provisioning
const RAPIDO_NET_CONF_PATH: &str = "net-conf";
// rapido-cut initramfs output path and rapido-vm QEMU input
const RAPIDO_DRACUT_OUT: &str = "initrds/myinitrd";
// default directory to write QEMU pidfiles
const RAPIDO_QEMU_PID_DIR: &str = "initrds";
// QEMU defaults: CLI with console redirection. Provide VMs with an RNG device.
const RAPIDO_QEMU_EXTRA_ARGS: &str = "-nographic -device virtio-rng-pci";

// parse /proc/version string, e.g. Linux version 6.17.0-2-default ...
fn host_kernel_vers_parse(kvers: &[u8]) -> io::Result<String> {
    match str::from_utf8(kvers) {
        Err(_) => Err(io::Error::from(io::ErrorKind::InvalidData)),
        Ok(s) => match s.strip_prefix("Linux version ") {
            None => Err(io::Error::from(io::ErrorKind::InvalidData)),
            Some(rel) => match rel.split_once([' ']) {
                Some((rel, _)) => Ok(rel.to_string()),
                None => Err(io::Error::from(io::ErrorKind::InvalidData)),
            },
        },
    }
}

// return the host kernel version based on /proc/version contents
pub fn host_kernel_vers() -> io::Result<String> {
    let kvers = fs::read("/proc/version")?;
    host_kernel_vers_parse(&kvers)
}

pub fn conf_src_or_host_kernel_vers(
    conf: &HashMap<String, String>
) -> io::Result<String> {
    match conf.get("KERNEL_SRC") {
        Some(ksrc) if !ksrc.is_empty() => {
            let b = fs::read(format!("{ksrc}/include/config/kernel.release"))?;
            let btrimmed = match b.strip_suffix(&[b'\n']) {
                Some(bt) => bt,
                None => &b,
            };
            Ok(String::from_utf8_lossy(btrimmed).to_string())
        },
        None | Some(_) => match conf.get("KERNEL_RELEASE") {
            Some(krel) => Ok(krel.clone()),
            None => host_kernel_vers(),
        },
    }
}

// return kmod dependencies based on @has_net and rapido @conf qemu parameters
pub fn conf_kmod_deps(conf: &HashMap<String, String>, has_net: bool) -> Vec<&str> {
    let mut deps = vec!();

    match conf.get("QEMU_EXTRA_ARGS") {
        Some(v) if v.contains("virtio-rng-pci") => deps.push("virtio_rng"),
        Some(_) | None => {},
    };

    if conf.get("VIRTFS_SHARE_PATH").is_some() {
        deps.extend(&["9pnet", "9pnet_virtio", "9p"]);
    }

    if has_net {
	deps.extend(&["virtio_net", "af_packet"]);
    }

    deps
}

// return an open file handle and path for rapido.conf, which may
// be @rapido_conf_path or overridden by RAPIDO_CONF env
pub fn host_rapido_conf_open(
    rapido_conf_path: &str,
) -> io::Result<(fs::File, PathBuf)> {
    // env file takes precedence
    match env::var("RAPIDO_CONF") {
        Ok(c) => {
            match fs::File::open(&c) {
                Err(e) if e.kind() == io::ErrorKind::NotFound => {
                    Err(io::Error::new(
                        io::ErrorKind::InvalidInput,
                        format!("RAPIDO_CONF missing at {}", c)
                    ))
                },
                Err(e) => Err(e),
                Ok(f) => Ok((f, PathBuf::from(c))),
            }
        },
        Err(env::VarError::NotPresent) => {
            let f = fs::File::open(rapido_conf_path)?;
            Ok((f, PathBuf::from(rapido_conf_path)))
        },
        Err(env::VarError::NotUnicode(_)) => {
            Err(io::Error::from(io::ErrorKind::InvalidInput))
        },
    }
}

pub fn conf_defaults() -> HashMap<String, String> {
    HashMap::from([
        ("DRACUT_OUT".to_string(), RAPIDO_DRACUT_OUT.to_string()),
        ("QEMU_PID_DIR".to_string(), RAPIDO_QEMU_PID_DIR.to_string()),
        ("VM_NET_CONF".to_string(), RAPIDO_NET_CONF_PATH.to_string()),
        ("QEMU_EXTRA_ARGS".to_string(), RAPIDO_QEMU_EXTRA_ARGS.to_string()),
    ])
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;

    struct TempDir {
        pub dir: PathBuf,
        pub dirname: String,
    }
    impl TempDir {
        // create a random temporary directory under CWD.
        // The directory will be cleaned up when TempDir goes out of scope.
        pub fn new() -> TempDir {
            let mut b = [0u8; 16];
            let mut dirname = String::from("test-rapido-lib-");
            fs::File::open("/dev/urandom").unwrap().read_exact(&mut b).unwrap();
            for i in &b {
                dirname.push_str(&format!("{:02x}", i));
            }

            fs::create_dir(&dirname).unwrap();
            eprintln!("created tmp dir: {}", dirname);
            TempDir { dir: PathBuf::from(&dirname), dirname }
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            assert!(self.dir.is_dir());
            // scary but does not follow symlinks so should be okay
            fs::remove_dir_all(&self.dir).unwrap();
            eprintln!("removed tmp dir: {}", self.dir.display());
        }
    }

    #[test]
    fn test_host_kernel_vers_parse() {
        let line = b"Linux version 6.17.0-2-default (geeko@buildhost) (gcc (SUSE Linux) 15.2.0, GNU ld (GNU Binutils; openSUSE Tumbleweed) 2.43.1.20241209-10) #1 SMP PREEMPT_DYNAMIC Thu Oct  2 08:12:40 UTC 2025 (190326b)";
        assert_eq!(host_kernel_vers_parse(line).unwrap(), "6.17.0-2-default");
    }

    #[test]
    fn test_conf_kmod_deps() {
        let conf: HashMap<String, String> = HashMap::from([
            ("QEMU_EXTRA_ARGS".to_string(), "-device virtio-rng-pci".to_string())
        ]);
        let kmods = conf_kmod_deps(&conf, true);
        assert!(kmods.contains(&"virtio_rng"));
        assert!(kmods.contains(&"virtio_net"));
    }

    #[test]
    fn test_conf_parse_from_defaults() {
        let td = TempDir::new();
        let conf_path = format!("{}/rapido.conf", td.dirname);
        fs::write(&conf_path, b"DRACUT_OUT=thisfile").unwrap();
        let mut c = conf_defaults();
        let (f, p) = host_rapido_conf_open(&conf_path).unwrap();
        kv_conf::kv_conf_process_append(io::BufReader::new(f), &mut c)
            .expect("failed to process conf");
        // explicitly set by rapido.conf
        assert_eq!(c.get("DRACUT_OUT"), Some("thisfile".to_string()).as_ref());
        // set as default
        assert!(c.get("QEMU_EXTRA_ARGS").unwrap().contains("-nographic"));
        assert_eq!(p, PathBuf::from(conf_path));
    }
}
