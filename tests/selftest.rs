// SPDX-License-Identifier: (GPL-2.0 OR GPL-3.0)
// Copyright (C) 2026 SUSE S.A.
use std::env;
use std::fs;
use std::io::{self, BufRead, Write};
use std::process::{Command, Stdio};

extern crate test_utils;

fn selftest_generate_conf(tmpd: &str) -> String {
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
        QEMU_PID_DIR=\"{tmpd}\""
    );
    conf_fh.write_all(conf.as_bytes()).unwrap();
    conf_fh.flush().unwrap();
    conf_path
}

#[test]
fn boot_simple_example() {
    let td = test_utils::TempDir::new();
    let conf = selftest_generate_conf(&td.dirname);
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
    let conf = selftest_generate_conf(&td.dirname);
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
