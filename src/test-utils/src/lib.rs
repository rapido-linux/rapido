// SPDX-License-Identifier: (GPL-2.0 OR GPL-3.0)
// Copyright (C) 2026 SUSE S.A.
use std::fs;
use std::io::Read;
use std::path::PathBuf;

pub struct TempDir {
    pub dir: PathBuf,
    pub dirname: String,
}

impl TempDir {
    // create a random temporary directory under CWD.
    // The directory will be cleaned up when TempDir goes out of scope.
    pub fn new() -> TempDir {
        let mut b = [0u8; 16];
        let mut dirname = String::from("test-rapido-");
        fs::File::open("/dev/urandom")
            .unwrap()
            .read_exact(&mut b)
            .unwrap();
        for i in &b {
            dirname.push_str(&format!("{:02x}", i));
        }
        fs::create_dir(&dirname).unwrap();
        TempDir {
            dir: PathBuf::from(&dirname),
            dirname,
        }
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        assert!(self.dir.is_dir());
        fs::remove_dir_all(&self.dir).unwrap();
    }
}
