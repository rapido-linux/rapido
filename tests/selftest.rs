// SPDX-License-Identifier: (GPL-2.0 OR GPL-3.0)
// Copyright (C) 2026 SUSE S.A.
use std::env;
use std::fs;
use std::io::{self, BufRead, Write};
use std::process::{Command, Stdio};

extern crate test_utils;

fn selftest_generate_conf(tmpd: &str, kvs: Option<&str>) -> String {
    let conf_path = format!("{tmpd}/r.conf");
    // use example as default conf. TODO: rely on sensible defaults w/o a conf
    fs::copy(format!("./rapido.conf.example"), &conf_path).unwrap();

    let mut conf_fh = fs::OpenOptions::new()
        .write(true)
        .append(true)
        .open(&conf_path)
        .unwrap();

    for key in ["KERNEL_SRC", "KERNEL_INSTALL_MOD_PATH"] {
        match env::var(key) {
            // use any kernel set by caller via env var
            Ok(v) => conf_fh
                .write_all(format!("{key}={v}\n").as_bytes())
                .unwrap(),
            Err(env::VarError::NotPresent) => {}
            Err(e) => panic!("unexpected env error {}", e),
        }
    }

    let conf = format!(
        "QEMU_EXTRA_KERNEL_PARAMS=\"loglevel=0\"
        QEMU_EXTRA_ARGS=\"-monitor none -serial stdio -nographic -device virtio-rng-pci\"
        DRACUT_OUT=\"{tmpd}/myinitrd\"
        QEMU_PID_DIR=\"{tmpd}\"\n"
    );
    conf_fh.write_all(conf.as_bytes()).unwrap();
    if kvs.is_some() {
        conf_fh.write_all(kvs.unwrap().as_bytes()).unwrap();
    }
    conf_fh.flush().unwrap();
    conf_path
}

#[test]
fn boot_simple_example() {
    let td = test_utils::TempDir::new();
    let conf = selftest_generate_conf(&td.dirname, None);
    // Use timeout for now, as std rust doesn't appear to offer kill() hooks.
    // Perhaps unix::process::ChildExt send_signal() in future?
    let mut proc = Command::new("timeout")
        // cargo test only builds debug binaries, so override rapido's path
        .env("RAPIDO_BIN_PATH", "target/debug")
        .env("RAPIDO_CONF", conf)
        .args(&["60s", "./rapido", "cut", "simple-example"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("rapido failed to start");
    let mut stdin = proc.stdin.take().unwrap();
    let stdout = proc.stdout.take().unwrap();

    for line in io::BufReader::new(stdout).lines() {
        let l = line.unwrap();
        if l.contains("Rapido scratch VM running") {
            stdin.write_all(b"shutdown\n").unwrap();
            stdin.flush().unwrap();
        }
    }

    let status = proc.wait().unwrap();
    assert!(status.success(), "bad status");
}

// simple-example runner with separate cut + boot invocations
#[test]
fn separate_cut_boot() {
    let td = test_utils::TempDir::new();
    let conf = selftest_generate_conf(&td.dirname, None);
    let mut proc = Command::new("timeout")
        .env("RAPIDO_BIN_PATH", "target/debug")
        .env("RAPIDO_CONF", &conf)
        .args(&["60s", "./rapido", "cut", "-B", "simple-example"])
        .stdout(Stdio::piped())
        .spawn()
        .expect("rapido failed to start");
    let stdout = proc.stdout.take().unwrap();

    for line in io::BufReader::new(stdout).lines() {
        if line.unwrap().contains("myinitrd written") {
            break;
        }
    }

    let status = proc.wait().unwrap();
    assert!(status.success(), "bad status");

    let mut proc = Command::new("timeout")
        .env("RAPIDO_BIN_PATH", "target/debug")
        .env("RAPIDO_CONF", &conf)
        .args(&["60s", "./rapido", "boot"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("rapido failed to start");
    let mut stdin = proc.stdin.take().unwrap();
    let stdout = proc.stdout.take().unwrap();
    let mut state = 0;
    let mut awaiting = "Rapido scratch VM running";

    for line in io::BufReader::new(stdout).lines() {
        if line.unwrap().contains(awaiting) {
            state += 1;
            eprintln!("got {}, moved to state {}", &awaiting, state);
            match state {
                // reboot and await boot msg again
                1 => {
                    stdin.write_all(b"reboot\n").unwrap();
                    stdin.flush().unwrap();
                }
                // cd and await pwd in prompt
                2 => {
                    stdin.write_all(b"cd /root\n").unwrap();
                    stdin.flush().unwrap();
                    awaiting = "/root";
                }
                3 => {
                    stdin.write_all(b"shutdown\n").unwrap();
                    stdin.flush().unwrap();
                    break;
                }
                _ => panic!("invalid state"),
            }
        }
    }

    assert_eq!(state, 3);
    let status = proc.wait().unwrap();
    assert!(status.success(), "bad status");
}

// Boot two simple-example VMs in parallel. Check vm_num and pid files.
#[test]
fn parallel_boot() {
    let td = test_utils::TempDir::new();
    let conf = selftest_generate_conf(&td.dirname, None);
    let status = Command::new("timeout")
        .env("RAPIDO_BIN_PATH", "target/debug")
        .env("RAPIDO_CONF", &conf)
        .args(&["60s", "./rapido", "cut", "-B", "simple-example"])
        .stdout(Stdio::null())
        .status()
        .expect("rapido failed to start");
    assert!(status.success(), "bad status");

    let mut proc1 = Command::new("timeout")
        .env("RAPIDO_BIN_PATH", "target/debug")
        .env("RAPIDO_CONF", &conf)
        .args(&["60s", "./rapido", "boot"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("rapido failed to start");
    let mut stdin1 = proc1.stdin.take().unwrap();
    let stdout1 = proc1.stdout.take().unwrap();

    let mut state = 0;
    let mut awaiting = "Rapido scratch VM running";
    for line in io::BufReader::new(stdout1).lines() {
        let l = line.unwrap();
        if l.contains(awaiting) {
            state += 1;
            eprintln!("got {}, moved to state {}", &awaiting, state);
            match state {
                1 => {
                    stdin1.write_all(b"cat /proc/cmdline\n").unwrap();
                    stdin1.flush().unwrap();
                    awaiting = "rapido.vm_num=1";
                }
                2 => {
                    // keep running for pidfile check
                    break;
                }
                _ => panic!("invalid state"),
            }
        }
    }
    assert_eq!(state, 2);

    let mut proc2 = Command::new("timeout")
        .env("RAPIDO_BIN_PATH", "target/debug")
        .env("RAPIDO_CONF", &conf)
        .args(&["60s", "./rapido", "boot"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("rapido failed to start");
    let mut stdin2 = proc2.stdin.take().unwrap();
    let stdout2 = proc2.stdout.take().unwrap();

    let mut state = 0;
    let mut awaiting = "Rapido scratch VM running";
    for line in io::BufReader::new(stdout2).lines() {
        let l = line.unwrap();
        if l.contains(awaiting) {
            state += 1;
            eprintln!("got {}, moved to state {}", &awaiting, state);
            match state {
                1 => {
                    stdin2.write_all(b"cat /proc/cmdline\n").unwrap();
                    stdin2.flush().unwrap();
                    awaiting = "rapido.vm_num=2";
                }
                2 => {
                    // keep running for pidfile check
                    break;
                }
                _ => panic!("invalid state"),
            }
        }
    }
    assert_eq!(state, 2);

    let vm1_pid = fs::read_to_string(format!("{}/rapido_vm1.pid", &td.dirname)).unwrap();
    let vm2_pid = fs::read_to_string(format!("{}/rapido_vm2.pid", &td.dirname)).unwrap();
    // drop newline and any garbage after it (yes, I've seen garbage here)
    let vm1_pid = vm1_pid.split_whitespace().next().unwrap();
    let vm2_pid = vm2_pid.split_whitespace().next().unwrap();
    assert!(fs::exists(format!("/proc/{}", vm1_pid)).unwrap());
    assert!(fs::exists(format!("/proc/{}", vm2_pid)).unwrap());

    stdin1.write_all(b"shutdown\n").unwrap();
    stdin1.flush().unwrap();
    stdin2.write_all(b"shutdown\n").unwrap();
    stdin2.flush().unwrap();

    let status = proc1.wait().unwrap();
    assert!(status.success(), "bad status");
    let status = proc2.wait().unwrap();
    assert!(status.success(), "bad status");
}

// exercise -f and -x post-autorun parameters
#[test]
fn post_autorun_exec() {
    let td = test_utils::TempDir::new();
    let conf = selftest_generate_conf(&td.dirname, None);

    let ar_str = "echo post autorun script passed as string";
    let ar_file = format!("{}/postautorun.sh", &td.dirname);
    fs::write(&ar_file, "echo post autorun script passed as file").unwrap();

    let mut proc = Command::new("timeout")
        .env("RAPIDO_BIN_PATH", "target/debug")
        .env("RAPIDO_CONF", &conf)
        .args(&[
            "60s",
            "./rapido",
            "cut",
            "-x",
            &ar_str,
            "-f",
            &ar_file,
            "simple-example",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("rapido failed to start");
    let mut stdin = proc.stdin.take().unwrap();
    let stdout = proc.stdout.take().unwrap();
    let mut state = 0;
    let mut awaiting = "Rapido scratch VM running";

    for line in io::BufReader::new(stdout).lines() {
        let l = line.unwrap();
        if l.contains(awaiting) {
            state += 1;
            eprintln!("got {}, moved to state {}", &awaiting, state);
            match state {
                1 => awaiting = "post autorun script passed as string",
                2 => awaiting = "post autorun script passed as file",
                3 => {
                    stdin.write_all(b"shutdown\n").unwrap();
                    stdin.flush().unwrap();
                    break;
                }
                _ => panic!("invalid state"),
            }
        }
    }

    assert_eq!(state, 3);
    assert!(proc.wait().unwrap().success(), "bad status");

    // same again, but change order of execution
    let mut proc = Command::new("timeout")
        .env("RAPIDO_BIN_PATH", "target/debug")
        .env("RAPIDO_CONF", &conf)
        .args(&[
            "60s",
            "./rapido",
            "cut",
            "-f",
            &ar_file,
            "-x",
            &ar_str,
            "-f",
            &ar_file,
            "simple-example",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("rapido failed to start");
    let mut stdin = proc.stdin.take().unwrap();
    let stdout = proc.stdout.take().unwrap();
    let mut state = 0;
    let mut awaiting = "Rapido scratch VM running";

    for line in io::BufReader::new(stdout).lines() {
        let l = line.unwrap();
        if l.contains(awaiting) {
            state += 1;
            eprintln!("got {}, moved to state {}", &awaiting, state);
            match state {
                1 => awaiting = "post autorun script passed as file",
                2 => awaiting = "post autorun script passed as string",
                3 => awaiting = "post autorun script passed as file",
                4 => {
                    stdin.write_all(b"shutdown\n").unwrap();
                    stdin.flush().unwrap();
                    break;
                }
                _ => panic!("invalid state"),
            }
        }
    }

    assert_eq!(state, 4);
    assert!(proc.wait().unwrap().success(), "bad status");
}

// Check net-conf hostnames are propagated through to VMs
#[test]
fn net_conf_hostname() {
    let td = test_utils::TempDir::new();
    let hn = "vm1-test-hostname";
    fs::create_dir_all(format!("{}/net-conf/vm1", &td.dirname)).unwrap();
    fs::write(format!("{}/net-conf/vm1/hostname", &td.dirname), hn).unwrap();
    let netconf_kv = format!("VM_NET_CONF=\"{}/net-conf\"\n", &td.dirname);
    let conf = selftest_generate_conf(&td.dirname, Some(&netconf_kv));

    let mut proc = Command::new("timeout")
        .env("RAPIDO_BIN_PATH", "target/debug")
        .env("RAPIDO_CONF", &conf)
        .args(&["60s", "./rapido", "cut", "simple-example"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("rapido failed to start");
    let mut stdin = proc.stdin.take().unwrap();
    let stdout = proc.stdout.take().unwrap();
    let mut state = 0;
    let mut awaiting = "Rapido scratch VM running";

    for line in io::BufReader::new(stdout).lines() {
        let l = line.unwrap();
        if l.contains(awaiting) {
            state += 1;
            eprintln!("got {}, moved to state {}", &awaiting, state);
            match state {
                1 => {
                    stdin.write_all(b"cat /proc/sys/kernel/hostname\n").unwrap();
                    stdin.flush().unwrap();
                    awaiting = hn;
                }
                2 => {
                    stdin.write_all(b"shutdown\n").unwrap();
                    stdin.flush().unwrap();
                    break;
                }
                _ => panic!("invalid state"),
            }
        }
    }

    assert_eq!(state, 2);
    assert!(proc.wait().unwrap().success(), "bad status");
}
