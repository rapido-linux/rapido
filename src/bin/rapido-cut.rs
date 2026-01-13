// SPDX-License-Identifier: (GPL-2.0 OR GPL-3.0)
// Copyright (C) 2025 SUSE LLC
use std::collections::{HashMap, HashSet};
use std::convert::TryFrom;
use std::env;
use std::fs;
use std::io;
use std::io::Seek;
use std::io::Write;
use std::path::{self, Path, PathBuf, Component};

use elf::abi;
use elf::ElfStream;
use elf::endian::AnyEndian;

use crosvm::argument::{self, Argument};
mod kmod;
use kmod::kmod_context::{KmodContext, ModuleStatus, MODULE_DB_FILES};
extern crate kv_conf;

// We should probably allow default search paths to be set at build time.
// On usr-merge systems, /X may be a symlink to /usr/X .
const BIN_PATHS: [&str; 5] = ["/usr/bin", "/usr/sbin", "/usr/lib/systemd", "/bin", "/sbin"];
// Extra search paths may be added at runtime via ELF RUNPATH/LibRunPath.
// x86_64-linux-gnu is for Debian/Ubuntu.
const LIB_PATHS: [&str; 5] = ["/usr/lib64", "/usr/lib", "/lib64", "/lib", "/usr/lib/x86_64-linux-gnu"];
// FIXME: don't assume cwd parent location
const MANIFEST_PATHS: [&str; 1] = ["manifest"];
// keys which can be used in manifest files (matching cli parameters)
const MANIFEST_KEYS: [&str; 5] = ["install", "try_install", "include", "kmods", "autorun"];
// FIXME: we shouldn't assume rapido-init location
const RAPIDO_INIT_PATH: &str = "target/release/rapido-init";
// FIXME: don't assume cwd location
const RAPIDO_BASH_RC_PATH: &str = "vm_autorun.env";

// XXX use next: 1<<0;
const GATHER_ITEM_IGNORE_PARENT: u32 =  1<<1;

// Don't print debug messages on release builds...
#[cfg(debug_assertions)]
macro_rules! dout {
    ($($l:tt)*) => { println!($($l)*); }
}
#[cfg(not(debug_assertions))]
macro_rules! dout {
    ($($l:tt)*) => {};
}

struct Fsent {
    path: PathBuf,
    md: fs::Metadata,
}

// TODO: merge with GatherEnt, with a static option too?
#[derive(PartialEq, Debug)]
struct GatherItem {
    src: PathBuf,
    dst: PathBuf,
    flags: u32,
}

struct GatherData {
    items: Vec<GatherItem>,
    // offset that we are currently processing
    off: usize,
}

#[derive(PartialEq, Debug)]
enum GatherEnt {
    // Name String may be an absolute host-source-path or a relative path
    // resolved via path_stat(). Destination matches source.
    // ELF dependencies are gathered for all Name* types if an execute mode
    // flag is present on the source file.
    Name(String),
    NameStatic(&'static str),
    // Same as above, but destination is explicitly provided.
    NameDst(&'static str, &'static str),
    // Ignore if missing, instead of aborting.
    NameTry(String),
    // Same as Name, except search LIB_PATHS. Lib* types trigger ELF dependency
    // gathering regardles of mode flags.
    Lib(String),
    // library with extra search path(s) from ELF RUNPATH
    LibRunPath(String, Vec<String>),
    // Same as Name, except search MANIFEST_PATHS
    Manifest(String),
}

struct Gather {
    // Dependencies (elf, kmod, etc.) are added to the end of the gather
    // list as they are found.
    names: Vec<GatherEnt>,
    // offset that we are currently processing
    off: usize,
}

// We *should* be running as an unprivileged process, so don't filter or block
// access to parent or special paths; this should all be handled by the OS.
fn path_stat(ent: &GatherEnt) -> Result<Fsent, io::Error> {
    let name: &str = match ent {
        GatherEnt::Name(n) => &n,
        GatherEnt::NameDst(n, _) => n,
        GatherEnt::NameStatic(n) => n,
        GatherEnt::NameTry(n) => &n,
        GatherEnt::Lib(n) => &n,
        // it might be cleaner to add an extra enum for paths with separator...
        GatherEnt::LibRunPath(n, _) if n.contains(path::MAIN_SEPARATOR_STR) => &n,
        GatherEnt::LibRunPath(n, paths) => {
            for dir in paths.iter() {
                let p = PathBuf::from(dir).join(n);
                if let Ok(md) = fs::symlink_metadata(&p) {
                    return Ok(Fsent {path: p, md: md});
                }
            }
            // fallback to LIB_PATHS search
            &n
        }
        GatherEnt::Manifest(n) => &n,
    };

    dout!("resolving path for {:?}", name);
    // if name has any separator in it then we should handle it as a relative
    // or absolute path. This should be close enough as a check.
    if name.contains(path::MAIN_SEPARATOR_STR) {
        dout!("using relative / absolute path {:?} as-is", name);
        return match fs::symlink_metadata(name) {
            Ok(md) => Ok(Fsent {
                path: path::absolute(name).expect("absolute failed for good path"),
                md: md
            }),
            Err(_) => {
                return Err(io::Error::new(
                    io::ErrorKind::NotFound,
                    format!("{} missing", name)
                ));
            }
        }
    }

    // TODO: set search_paths with name above. Tuple assignment didn't work for me.
    let search_paths: &[&str] = match ent {
        GatherEnt::LibRunPath(_, _) | GatherEnt::Lib(_) => &LIB_PATHS,
        GatherEnt::Manifest(_) => &MANIFEST_PATHS,
        _ => &BIN_PATHS,
    };

    for dir in search_paths.iter() {
        let p = PathBuf::from(dir).join(name);
        if let Ok(md) = fs::symlink_metadata(&p) {
            return Ok(Fsent {path: p, md: md});
        }
    }

    return Err(io::Error::new(
        io::ErrorKind::NotFound,
        match ent {
            GatherEnt::LibRunPath(_, p) => {
                format!("{} missing from: {:?} & {:?}", name, p, search_paths)
            }
            _ => format!("{} missing from: {:?}", name, search_paths),
        }
    ));
}

// Parse ELF DT_NEEDED entries to gather shared object dependencies.
// DT_RUNPATH entries are retained as extra library search paths.
// XXX NameTry bins result in Lib or LibRunPath entries; if a binary
// is installed then it's reasonable to require presence of libs.
fn elf_deps(
    f: &fs::File,
    path: &Path,
    dups_filter: &mut HashSet<String>
) -> Result<Vec<GatherEnt>, io::Error> {
    let mut ret: Vec<GatherEnt> = vec![];

    let mut file = match ElfStream::<AnyEndian, _>::open_stream(f) {
        Ok(f) => f,
        Err(_) => {
            // ParseError::BadOffset / ParseError::BadMagic is returned
            // immediately for empty / non-elf, which we want to ignore.
            dout!("file {:?} not an elf", path);
            return Err(io::Error::from(io::ErrorKind::InvalidInput));
        }
    };

    let dynamics = match file.dynamic() {
        Ok(d) => {
            if d.is_none() {
                eprintln!("Failed to find .dynamic for {:?}", path);
                return Ok(ret);
            }
            d.unwrap()
        },
        Err(e) => {
            eprintln!("{:?} elf .dynamic error: {:?}", path, e);
            return Err(io::Error::from(io::ErrorKind::InvalidData));
        },
    };

    let mut runpath_offs: Vec<usize> = vec!();
    let mut needed_offs: Vec<usize> = vec!();
    for dyna in dynamics.iter() {
        let v = match dyna.d_tag {
            abi::DT_NEEDED => &mut needed_offs,
            abi::DT_RUNPATH => &mut runpath_offs,
            _ => continue,
        };

        match usize::try_from(dyna.d_val()) {
            Err(_) => {
                eprintln!("{:?} bad elf dynamic off {:?}", path, dyna);
                return Err(io::Error::from(io::ErrorKind::InvalidData));
            }
            Ok(str_off) => v.push(str_off),
        }
    }

    let dynsyms_strs = match file.dynamic_symbol_table() {
        Err(e) => {
            eprintln!("{:?} bad elf dynamic sym table: {:?}", path, e);
            return Err(io::Error::from(io::ErrorKind::InvalidData));
        },
        Ok(tup) => {
            if tup.is_none() {
                dout!("no tables for {:?}", path);
                return Ok(ret);
            }
            let (_, strs) = tup.unwrap();
            strs
        },
    };

    // get full list of runpaths first
    let runpaths: Vec<String> = runpath_offs.into_iter().filter_map(|o| {
        match dynsyms_strs.get(o) {
            Err(_) => None,
            Ok(s) => Some(s.to_string()),
        }
    }).collect();

    for str_off in needed_offs {
        match dynsyms_strs.get(str_off) {
            Ok(sraw) => {
                let s = sraw.to_string();
                if dups_filter.insert(s.clone()) {
                    dout!("new elf dependency({:?}): {:?}", str_off, s);
                    if runpaths.len() > 0 {
                        // would be nice to avoid cloning for every lib here:
                        // perhaps add a single GatherEnt::PathPush/Pop pair?
                        // RUNPATH rare enough that it's prob not worth it.
                        ret.push(GatherEnt::LibRunPath(s, runpaths.clone()));
                    } else {
                        ret.push(GatherEnt::Lib(s));
                    }
                } else {
                    dout!("duplicate elf dependency({:?}): {:?}", str_off, sraw);
                }
            },
            Err(e) => {
                eprintln!("{:?} bad elf dynamic sym table: {:?}", path, e);
                return Err(io::Error::from(io::ErrorKind::InvalidData));
            },
        };
    }

    Ok(ret)
}

// XXX: symlinks in parent ancestry will be archived as dirs
// FIXME: how does this handle relative "" parents?
// @child_amd provides the child metadata, which is used to mock up metadata
// for parent directories.
fn gather_archive_dirs<W: Seek + Write>(
    path: Option<&Path>,
    child_amd: &cpio::ArchiveMd,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {
    // path may come from parent(), hence Option
    let p = match path {
        None => return Ok(()),
        // don't canonicalize dirs: dest path may not match host
        Some(p) => p,
    };

    // path_stat() and dst assignment call absolute()
    if !p.is_absolute() {
        panic!("non-absolute path, check path_stat and dst paths");
    }

    if paths_seen.contains(p) {
        dout!("ignoring seen directory and parents: {:?}", p);
        return Ok(());
    }

    // mock up md to use for any parent directories. 0111: allow traversal
    let parent_dirs_amd = cpio::ArchiveMd{
        mode: match child_amd.mode & cpio::S_IFMT {
            cpio::S_IFDIR => child_amd.mode,
            _ => (child_amd.mode & !cpio::S_IFMT) | cpio::S_IFDIR | 0111,
        },
        nlink: 2,
        rmajor: 0,
        rminor: 0,
        len: 0,
        ..*child_amd
    };

    // order is important: parent dirs must be archived before children
    let mut here = PathBuf::from("/");
    for comp in p.components() {
        match comp {
            Component::RootDir => continue,
            Component::CurDir | Component::ParentDir => {
                // FIXME: absolute() does leave ParentDir components!
                panic!("got CurDir or ParentDir after canonicalization");
            },
            Component::Prefix(_) => {
                eprintln!("non-Unix path prefixes not supported");
                return Err(io::Error::from(io::ErrorKind::InvalidInput));
            },
            Component::Normal(c) => here.push(c),
        }

        if !paths_seen.insert(here.clone()) {
            dout!("ignoring seen directory: {:?}", here);
            continue;
        }

        cpio::archive_path(cpio_state, &here, &parent_dirs_amd, &mut cpio_writer)?;
        dout!("archived dir: {:?}", here);
    }

    Ok(())
}

fn gather_archive_elfs<W: Seek + Write>(
    elfs: &mut Gather,
    libs_seen: &mut HashSet<String>,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {

    while let Some(ent) = elfs.names.get(elfs.off) {
        elfs.off += 1;

        let got = match path_stat(&ent) {
            Err(e) => {
                if let GatherEnt::NameTry(_) = ent {
                    continue;
                }
                return Err(e);
            }
            Ok(g) => g,
        };
        let (dst, lib_ent) = match ent {
            GatherEnt::NameDst(_, d) => (&path::absolute(d)?, false),
            GatherEnt::LibRunPath(_, _) | GatherEnt::Lib(_) => (&got.path, true),
            _ => (&got.path, false),
        };

        let amd = cpio::ArchiveMd::from(&cpio_state, &got.md)?;
        gather_archive_dirs(
            dst.parent(),
            &amd,
            paths_seen,
            cpio_state,
            &mut cpio_writer
        )?;
        match amd.mode & cpio::S_IFMT {
            cpio::S_IFLNK => {
                // symlinks are tricky, so provide some restrictions:
                // - the host path must match the initramfs dest path
                // - targets be resolvable; no dangling / arbitrary links
                // - multiple indirect links will be collapsed
                if let GatherEnt::NameDst(_, _) = ent {
                    eprintln!("symlink source and cpio dest paths must match");
                    return Err(io::Error::from(io::ErrorKind::InvalidInput));
                }
                let canon_tgt = match got.path.canonicalize() {
                    Err(e) => {
                        eprintln!("{:?} canonicalize failed: {:?}", got.path, e);
                        continue;
                    },
                    Ok(t) => t,
                };
                cpio::archive_symlink(
                    cpio_state,
                    &got.path,
                    &amd,
                    &canon_tgt,
                    &mut cpio_writer
                )?;
                dout!("archived symlink: {:?} ({:?})", got.path, canon_tgt);

                // could add a Path ent type to avoid String conversion here...
                if let Ok(t) = canon_tgt.into_os_string().into_string() {
                    let tgtent = match lib_ent {
                        true => GatherEnt::Lib(t),
                        false => GatherEnt::Name(t),
                    };
                    elfs.names.push(tgtent);
                } else {
                    eprintln!("non utf-8 symlink target {:?}", &got.path);
                    return Err(io::Error::from(io::ErrorKind::InvalidInput));
                }
            },
            cpio::S_IFREG if amd.len > 0 => {
                let mut f = fs::OpenOptions::new().read(true).open(&got.path)?;

                if amd.mode & 0o111 != 0 || lib_ent {
                    // ignore elf_deps errors: file is non-elf or malformed
                    if let Ok(mut d) = elf_deps(&f, &got.path, libs_seen) {
                        elfs.names.append(&mut d);
                    }
                    // don't check for '#!' interpreters like Dracut, it's messy

                    f.seek(io::SeekFrom::Start(0))?;
                }
                cpio::archive_file(cpio_state, dst, &amd, &f, &mut cpio_writer)?;
                dout!("archived elf: {:?}→{:?}", got.path, dst);
            },
            _ => {
                cpio::archive_path(cpio_state, &dst, &amd, &mut cpio_writer)?;
                dout!("archived other: {:?}→{:?}", got.path, dst);
            },
        };
    }

    Ok(())
}

fn archive_kmod_path<W: Seek + Write>(
    src: &Path,
    dst: &Path,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {
    let md = fs::symlink_metadata(src)?;
    let amd = cpio::ArchiveMd::from(cpio_state, &md)?;
    gather_archive_dirs(
        dst.parent(),
        &amd,
        paths_seen,
        cpio_state,
        &mut cpio_writer
    )?;

    let kmod_f = fs::File::open(src)?;
    cpio::archive_file(
        cpio_state,
        dst,
        &amd,
        &kmod_f,
        cpio_writer,
    )?;
    dout!("archived kmod: {:?} -> {:?}", src, dst);
    Ok(())
}

// XXX: Tumbleweed kmod is patched to use "/usr/lib/modules", while
// mainline kernel and Leap 15 use "/lib/modules". Worse still, there's no
// easy way to specify the directory for modprobe, so we use symlinks. Booo.
// See https://src.opensuse.org/pool/kmod/src/branch/factory/README.usrmerge
fn archive_kmods_symlink<W: Seek + Write>(
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {
    let libp = Path::new("/lib");
    let (p, tgt) = match paths_seen.contains(libp) {
        false => (libp, Path::new("/usr/lib")),
        true => (Path::new("/lib/modules"), Path::new("/usr/lib/modules")),
    };
    let amd = cpio::ArchiveMd{
        nlink: 1,
        mode: cpio::S_IFLNK | 0o777,
        uid: 0,
        gid: 0,
        mtime: 0,
        rmajor: 0,
        rminor: 0,
        len: 0,
    };
    cpio::archive_symlink(cpio_state, &p, &amd, &tgt, &mut cpio_writer)?;
    dout!("archived kmod symlink {:?} ({:?})", p, tgt);
    Ok(())
}

fn gather_archive_kmod_and_deps<W: Seek + Write>(
    name: &str,
    kmod_src_root: &Path,
    kmod_dst_root: &Path,
    context: &KmodContext,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {
    let root_mod = match context.find(name) {
        None => return Err(io::Error::from(io::ErrorKind::NotFound)),
        Some(m) if m.status == ModuleStatus::Builtin => {
            dout!("{} builtin", name);
            return Ok(());
        },
        Some(m) => m,
    };

    // Fail if root mod or hard deps are missing.
    // No recursive checking here; modules.dep entry is complete
    // and doesn't contain Builtins.
    let kmod_dst = kmod_dst_root.join(&root_mod.rel_path);
    if paths_seen.insert(kmod_dst.clone()) {
        let kmod_src = kmod_src_root.join(&root_mod.rel_path);
        archive_kmod_path(
            &kmod_src,
            &kmod_dst,
            paths_seen,
            cpio_state,
            &mut cpio_writer
        )?;
    } else {
        dout!("skipping duplicate kmod {:?} and all deps", &kmod_dst);
        return Ok(());
    }

    for dep_path in root_mod.hard_deps_paths.iter() {
        let kmod_dst = kmod_dst_root.join(&dep_path);
        if paths_seen.insert(kmod_dst.clone()) {
            let kmod_src = kmod_src_root.join(&dep_path);
            archive_kmod_path(
                &kmod_src,
                &kmod_dst,
                paths_seen,
                cpio_state,
                &mut cpio_writer
            )?;
        } else {
            dout!("skipping duplicate kmod {:?}", &kmod_dst);
        }
    }

    // Attempt to pull in soft and weak dependencies for root_mod.
    // Not sure if we should be checking root_mod dependents.
    for soft_mod in root_mod.soft_deps_pre.iter()
        .chain(root_mod.soft_deps_post.iter())
        .chain(root_mod.weak_deps.iter()) {
        let m = match context.find(soft_mod) {
            None => {
                dout!("{:?} soft / weak kernel dep not found", soft_mod);
                continue;
            },
            Some(m) if m.status == ModuleStatus::Builtin => continue,
            Some(m) => m,
        };
        let kmod_dst = kmod_dst_root.join(&m.rel_path);
        if paths_seen.insert(kmod_dst.clone()) {
            let kmod_src = kmod_src_root.join(&m.rel_path);
            match archive_kmod_path(
                &kmod_src,
                &kmod_dst,
                paths_seen,
                cpio_state,
                &mut cpio_writer
            ) {
                Err(e) if e.kind() == io::ErrorKind::NotFound => {
                    dout!("{:?} soft / weak kernel dep missing", &kmod_src);
                    continue;
                },
                Err(e) => return Err(e),
                Ok(_) => {},
            }
        } else {
            dout!("skipping duplicate kmod {:?}", &kmod_dst);
        }
    }
    Ok(())
}

fn gather_archive_kmods<W: Seek + Write>(
    conf: &HashMap<String, String>,
    kmods: &Vec<String>,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {
    let krel = rapido::conf_src_or_host_kernel_vers(&conf)?;
    let kmod_dst_root = PathBuf::from("/usr/lib/modules/").join(&krel);
    let kmod_src_root = match conf.get("KERNEL_INSTALL_MOD_PATH") {
        // should assert that KERNEL_SRC is set?
        Some(kmp) if !kmp.is_empty() => PathBuf::from(kmp).join(format!("lib/modules/{krel}")),
        None | Some(_) if kmod_dst_root.exists() => kmod_dst_root.clone(),
        None | Some(_) => {
            // assume that we have a non-Tumbleweed system
            PathBuf::from("/lib/modules/").join(&krel)
        },
    };

    archive_kmods_symlink(paths_seen, cpio_state, &mut cpio_writer)?;

    let kmod_ctx = match KmodContext::new(&kmod_src_root) {
        Err(e) => return Err(io::Error::new(io::ErrorKind::InvalidInput, e)),
        Ok(ctx) => ctx,
    };

    for name in kmods.iter() {
        match gather_archive_kmod_and_deps(
            &name,
            &kmod_src_root,
            &kmod_dst_root,
            &kmod_ctx,
            paths_seen,
            cpio_state,
            &mut cpio_writer
        ) {
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                return Err(io::Error::new(
                    io::ErrorKind::NotFound,
                    format!("{} missing from: {:?}", name, kmod_src_root)
                ));
            },
            Err(e) => return Err(e),
            Ok(_) => {},
        };
    }

    // add module_data_paths inside initrd
    for file_name in MODULE_DB_FILES.iter() {
        let data_dst_path = kmod_dst_root.join(file_name);
        if paths_seen.insert(data_dst_path.clone()) {
            let data_src_path = kmod_src_root.join(file_name);
            match archive_kmod_path(
                &data_src_path,
                &data_dst_path,
                paths_seen,
                cpio_state,
                &mut cpio_writer
            ) {
                Err(e) if e.kind() == io::ErrorKind::NotFound => {
                    dout!("Module data path {:?} missing", data_src_path);
                    // TODO: only install required, and return error if missing
                },
                Err(e) => return Err(e),
                Ok(_) => {},
            }
        }
    }

    Ok(())
}

fn gather_archive_data<W: Seek + Write>(
    data: &mut GatherData,
    paths_seen: &mut HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {

    // walk each src entry and append any newly found dirs for later traversal
    while let Some(item) = data.items.get(data.off) {
        data.off += 1;

        let src_md = match fs::symlink_metadata(&item.src) {
            Ok(md) => md,
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                return Err(io::Error::new(
                    io::ErrorKind::NotFound,
                    format!("{:?} missing", item.src)
                ));
            }
            Err(e) => return Err(e),
        };
        let src_amd = cpio::ArchiveMd::from(cpio_state, &src_md)?;

        if !paths_seen.insert(item.dst.clone()) {
            dout!("ignoring seen data path: {:?}", &item.dst);
            continue;
        }
        if item.flags & GATHER_ITEM_IGNORE_PARENT == 0 {
            gather_archive_dirs(
                item.dst.parent(),
                &src_amd,
                paths_seen,
                cpio_state,
                &mut cpio_writer
            )?;
        }

        match src_amd.mode & cpio::S_IFMT {
            // add any subdirs to gather list
            cpio::S_IFDIR => {
                cpio::archive_path(
                    cpio_state,
                    &item.dst,
                    &src_amd,
                    &mut cpio_writer
                )?;
                dout!("archived data dir: {:?}→{:?}", item.src, item.dst);

                let mut entries = fs::read_dir(&item.src)?
                    .map(|res| res.map(|e| e.file_name()))
                    .collect::<Result<Vec<_>, io::Error>>()?;
                // sort for reproducibility
                entries.sort();

                let cs = item.src.clone();
                let cd = item.dst.clone();
                for entry in entries {
                    // "." and ".." are filtered by fs::read_dir()
                    data.items.push(GatherItem {
                        src: cs.join(&entry),
                        dst: cd.join(&entry),
                        // we don't need to check for parent dir existence, as
                        // we just archived it.
                        flags: GATHER_ITEM_IGNORE_PARENT,
                    });
                }
            },
            // dataless files can use archive_path
            cpio::S_IFREG if src_amd.len > 0 => {
                let f = fs::OpenOptions::new().read(true).open(&item.src)?;
                cpio::archive_file(
                    cpio_state,
                    &item.dst,
                    &src_amd,
                    &f,
                    &mut cpio_writer
                )?;
                dout!("archived data file: {:?}→{:?}", item.src, item.dst);
            },
            cpio::S_IFLNK => {
                let tgt = fs::read_link(&item.src)?;
                // XXX don't follow data symlinks to archive their targets
                cpio::archive_symlink(
                    cpio_state,
                    &item.dst,
                    &src_amd,
                    &tgt,
                    &mut cpio_writer
                )?;
                dout!("archived data symlink: {:?}→{:?}", item.src, item.dst);
            },
            _ => {
                cpio::archive_path(
                    cpio_state,
                    &item.dst,
                    &src_amd,
                    &mut cpio_writer
                )?;
                dout!("archived data path: {:?}→{:?}", item.src, item.dst);
            },
        };
    }

    Ok(())
}

fn gather_manifest_entries(
    conf: &HashMap<String, String>,
    state: &mut CutState,
) -> io::Result<()> {
    while let Some(fest) = state.manifests.names.get(state.manifests.off) {
        state.manifests.off += 1;

        let got = path_stat(&fest)?;
        let f = fs::OpenOptions::new().read(true).open(&got.path)?;
        let mut fest_map = HashMap::new();
        if let Err(e) = kv_conf::kv_conf_process_append_separate(
            io::BufReader::new(f),
            &conf,
            &mut fest_map,
        ) {
            eprintln!("failed to process manifest {:?}: {:?}", got.path, e);
            return Err(e);
        }

        // Only a few options are supported ATM. In future we may wish to
        // support manifests with dependency manifests, but that might get
        // a little ugly WRT ordering (e.g. autorun sequence in reverse).
        for k in MANIFEST_KEYS {
            match fest_map.remove(k) {
                Some(v) => match args_process_one(k, Some(&v), state) {
                    Err(e) => {
                        eprintln!("manifest {:?} entry {}={}: {}", got.path, k, v, e);
                        return Err(io::Error::new(
                            io::ErrorKind::InvalidInput,
                            e.to_string()
                        ));
                    }
                    Ok(()) => {},
                }
                None => {},
            }
        }
        if !fest_map.is_empty() {
            eprintln!(
                "Manifest {:?} unsupported: {:?}\nSupported keys: {:?}",
                got.path,
                fest_map,
                MANIFEST_KEYS
            );
            return Err(io::Error::from(io::ErrorKind::InvalidInput));
        }
    }
    Ok(())
}

fn populate_default_symlinks<W: Seek + Write>(
    paths_seen: &HashSet<PathBuf>,
    cpio_state: &mut cpio::ArchiveState,
    mut cpio_writer: W,
) -> io::Result<()> {
    let amd = cpio::ArchiveMd{
            nlink: 1,
            mode: cpio::S_IFLNK | 0o777,
            uid: 0,
            gid: 0,
            mtime: 0,
            rmajor: 0,
            rminor: 0,
            len: 0,
    };

    // on Tumbleweed, bash won't start without this symlink. /lib64 may already
    // exist (e.g. it's a regular dir on Leap), so conditionally create it.
    let p = Path::new("/lib64");
    if !paths_seen.contains(p) {
        let tgt = Path::new("/usr/lib64");
        cpio::archive_symlink(cpio_state, p, &amd, tgt, &mut cpio_writer)?;
    }
    // xfstests (and others) hardcode /bin/bash
    let p = Path::new("/bin");
    if !paths_seen.contains(p) {
        let tgt = Path::new("/usr/bin");
        cpio::archive_symlink(cpio_state, p, &amd, tgt, &mut cpio_writer)?;
    }
    // kernel request_module() runs CONFIG_MODPROBE_PATH. On 15.6 it's under...
    let p = Path::new("/sbin");
    if !paths_seen.contains(p) {
        let tgt = Path::new("/usr/sbin");
        cpio::archive_symlink(cpio_state, p, &amd, tgt, &mut cpio_writer)?;
    } else {
        let p = Path::new("/sbin/modprobe");
        let tgt = Path::new("/usr/sbin/modprobe");
        if !paths_seen.contains(p) && paths_seen.contains(tgt) {
            cpio::archive_symlink(cpio_state, p, &amd, tgt, &mut cpio_writer)?;
        }
    }
    Ok(())
}

struct CutState {
    cpio_output_arg: Option<PathBuf>,
    elfs: Gather,
    kmods: Vec<String>,
    data: GatherData,
    autoruns: u32,
    manifests: Gather,
}

fn args_usage(params: &[Argument]) {
    argument::print_help("rapido-cut", "", params);
}

fn args_process_one(name: &str, value: Option<&str>, state: &mut CutState) -> argument::Result<()> {
    // unwrap: callers ensure value is Some if arg requires one
    match name {
        "output" => state.cpio_output_arg = Some(PathBuf::from(value.unwrap())),
        "install" => {
            let mut files: Vec<GatherEnt> = value
                .unwrap()
                .split_whitespace()
                .map(|f| GatherEnt::Name(f.to_string()))
                .collect();
            state.elfs.names.append(&mut files);
        }
        "try-install" | "try_install" => {
            let mut files: Vec<GatherEnt> = value
                .unwrap()
                .split_whitespace()
                .map(|f| GatherEnt::NameTry(f.to_string()))
                .collect();
            state.elfs.names.append(&mut files);
        }
        "kmods" => {
            let kmod_parsed: argument::Result<Vec<String>> = value
                .unwrap()
                .split_whitespace()
                .map(|f| {
                    f.parse().map_err(|_| argument::Error::InvalidValue {
                        value: f.to_owned(),
                        expected: String::from("MODULES must be utf-8 strings"),
                    })
                })
                .collect();
            state.kmods.append(&mut kmod_parsed?);
        }
        "include" => {
            let mut iter = value.unwrap().split_whitespace();
            while let Some(src) = iter.next() {
                match iter.next() {
                    None => return Err(argument::Error::InvalidValue {
                        value: src.to_string(),
                        expected: String::from("SRC DEST pairs"),
                    }),
                    Some(d) => {
                        let dst = PathBuf::from(d);
                        if !dst.is_absolute() {
                            return Err(argument::Error::InvalidValue {
                                value: d.to_string(),
                                expected: String::from(
                                    "DEST paths must be absolute"
                                ),
                            });
                        }
                        let gi = GatherItem {
                            src: PathBuf::from(src),
                            dst,
                            flags: 0,
                        };
                        // optimization: rsc paths first to speed up rapido-vm
                        if gi.dst.starts_with("/rapido-rsc") {
                            state.data.items.insert(0, gi);
                        } else {
                            state.data.items.push(gi);
                        }
                    },
                };
            }
        }
        "autorun" => {
            for file in value.unwrap().split_whitespace() {
                let src = PathBuf::from(file);
                if !src.is_file() {
                    return Err(argument::Error::InvalidValue {
                        value: file.to_owned(),
                        expected: String::from("file missing"),
                    });
                }
                let dst = match src.file_name() {
                    None => return Err(
                        argument::Error::InvalidValue {
                            value: file.to_owned(),
                            expected: String::from("bad file"),
                        }
                    ),
                    Some(n) if n.to_str().is_none() => return Err(
                        argument::Error::InvalidValue {
                            value: file.to_owned(),
                            expected: String::from("bad file"),
                        }
                    ),
                    Some(n) => PathBuf::from(&format!(
                        "/rapido_autorun/{:03}-{}",
                        state.autoruns,
                        n.to_str().unwrap()
                    )),
                };
                // TODO: it'd be better if we place these after the rapido-rsc
                // entries, so that the boot time rsc check is faster.

                state.data.items.push(
                    GatherItem { src, dst, flags: 0 }
                );
                state.autoruns += 1;
            }
        }
        "manifest" => {
            let mut manifests: Vec<GatherEnt> = value
                .unwrap()
                .split_whitespace()
                .map(|f| GatherEnt::Manifest(f.to_string()))
                .collect();
            state.manifests.names.append(&mut manifests);
        }
        "help" => return Err(argument::Error::PrintHelp),
        _ => unreachable!(),
    };
    Ok(())
}

fn args_process(state: &mut CutState) -> argument::Result<()> {
    let params = &[
        Argument::value(
            "output",
            "INITRAMFS",
            "Write initramfs archive to this file path."
        ),
        Argument::value(
            "install",
            "FILES",
            "Space separated list of files to archive. ELF dependencies are gathered too."
        ),
        Argument::value(
            "try-install",
            "FILES",
            "List of files to archive, if present, along with ELF dependencies."
        ),
        Argument::value(
            "kmods",
            "MODULES",
            "List of kernel modules to install with dependencies.",
        ),
        Argument::value(
            "include",
            "SRC_PATH DEST_PATH",
            "List of path pairs to install recursively.",
        ),
        Argument::value(
            "autorun",
            "PROGRAM",
            "List of files to execute on VM boot, in order.",
        ),
        Argument::value(
            "manifest",
            "FILES",
            "List of manifest files, as an alternative to params, e.g. install=bash",
        ),
        Argument::short_flag('h', "help", "Print help message."),
    ];

    let args = env::args().skip(1); // skip binary name
    let match_res = argument::set_arguments(args, params, |name, value| {
        args_process_one(name, value, state)
    });

    if let Err(e) = match_res {
        args_usage(params);
        return Err(e);
    }

    Ok(())
}

fn main() -> io::Result<()> {
    let mut state = CutState {
        cpio_output_arg: None,
        elfs: Gather {
            names: vec!(
                GatherEnt::NameDst(RAPIDO_INIT_PATH, "/rdinit"),
                // rapido-init core deps
                GatherEnt::NameStatic("mount"),
                GatherEnt::NameStatic("setsid"),
                GatherEnt::NameStatic("bash"),
                GatherEnt::NameStatic("stty"),
            ),
            off: 0,
        },
        // kmods currently only tracks user-requested modules.
        // Dependencies are omitted and missing mods aren't tracked.
        kmods: vec!(),
        data: GatherData {
            items: vec!(
                GatherItem {
                    src: PathBuf::from(RAPIDO_BASH_RC_PATH),
                    dst: PathBuf::from("/rapido.rc"),
                    flags: GATHER_ITEM_IGNORE_PARENT,
                },
            ),
            off: 0,
        },
        autoruns: 0,
        manifests: Gather {
            names: vec!(),
            off: 0,
        },
    };

    let conf = match rapido::host_rapido_conf_open(rapido::RAPIDO_CONF_PATH) {
        Err(e) if e.kind() == io::ErrorKind::NotFound => {
            eprintln!("no rapido.conf, using defaults");
            rapido::conf_defaults()
            // TODO: archive empty rapido.conf?
        },
        Err(e) => {
            eprintln!("failed to open rapido.conf: {:?}", e);
            return Err(e);
        },
        Ok((f, p)) => {
            let mut conf = rapido::conf_defaults();
            if let Err(e) = kv_conf::kv_conf_process_append(
                io::BufReader::new(f),
                &mut conf
            ) {
                eprintln!("failed to process {:?}: {:?}", p, e);
                return Err(e);
            }

            // TODO: immediately archive rapido.conf while still open here?
            state.data.items.push(
                GatherItem {
                    src: p,
                    dst: PathBuf::from("/rapido.conf"),
                    flags: GATHER_ITEM_IGNORE_PARENT,
                }
            );
            conf
        },
    };

    match args_process(&mut state) {
        Ok(p) => p,
        Err(argument::Error::PrintHelp) => return Ok(()),
        Err(e) => return Err(io::Error::new(io::ErrorKind::InvalidInput, e.to_string())),
    };

    // manifests files carry install/include/kmod/autorun directives
    gather_manifest_entries(&conf, &mut state)?;

    state.kmods.extend(
        rapido::conf_kmod_deps(&conf).into_iter().map(|s| s.to_string())
    );
    if state.kmods.len() > 0 {
        // TODO only install if we have non-builtin kmods!
        state.elfs.names.extend([GatherEnt::NameStatic("modprobe")]);
    }

    let cpio_props = cpio::ArchiveProperties{
        // Attempt 4K file data alignment within archive for Btrfs/XFS reflinks
        data_align: 4096,
        ..cpio::ArchiveProperties::default()
    };
    let mut cpio_state = cpio::ArchiveState::new(&cpio_props);
    let cpio_out_path = match state.cpio_output_arg {
        Some(p) => p,
        // unwrap: DRACUT_OUT set in conf_defaults()
        None => PathBuf::from(&conf.get("DRACUT_OUT").unwrap()),
    };

    let mut cpio_writer = match fs::OpenOptions::new()
        .read(false)
        .write(true)
        .create(true)
        // for rapido we normally want to truncate any existing output file
        .truncate(true)
        .open(&cpio_out_path) {
        Err(e) => {
            eprintln!("failed to open output at {:?}: {}", cpio_out_path, e);
            return Err(e);
        },
        Ok(f) => io::BufWriter::new(f),
    };

    // @libs_seen is an optimization to avoid resolving already-seen elf deps.
    let mut libs_seen: HashSet<String> = HashSet::new();
    // avoid archiving already-archived paths
    let mut paths_seen: HashSet<PathBuf> = HashSet::new();

    // optimization: rapido-rsc paths are parsed by rapido-vm so put them first
    gather_archive_data(
        &mut state.data,
        &mut paths_seen,
        &mut cpio_state,
        &mut cpio_writer
    )?;

    gather_archive_elfs(
        &mut state.elfs,
        &mut libs_seen,
        &mut paths_seen,
        &mut cpio_state,
        &mut cpio_writer
    )?;

    gather_archive_kmods(
        &conf,
        &state.kmods,
        &mut paths_seen,
        &mut cpio_state,
        &mut cpio_writer
    )?;

    populate_default_symlinks(&paths_seen, &mut cpio_state, &mut cpio_writer)?;

    let len = cpio::archive_trailer(&mut cpio_state, &mut cpio_writer)?;
    cpio_writer.flush()?;
    println!("initramfs {} written ({} bytes)", cpio_out_path.display(), len);

    Ok(())
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
        pub fn new() -> TempDir {
            let mut b = [0u8; 16];
            let mut dirname = String::from("test-rapido-cut-");
            fs::File::open("/dev/urandom").unwrap().read_exact(&mut b).unwrap();
            for i in &b {
                dirname.push_str(&format!("{:02x}", i));
            }
            fs::create_dir(&dirname).unwrap();
            TempDir { dir: PathBuf::from(&dirname), dirname }
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            assert!(self.dir.is_dir());
            fs::remove_dir_all(&self.dir).unwrap();
        }
    }

    #[test]
    fn test_gather_manifest() {
        let conf = rapido::conf_defaults();
        let td = TempDir::new();
        let tfest = format!("{}/testmanifest.fest", td.dirname);
        fs::write(
            &tfest,
            "install=\"bash\"\ninclude=\"${VM_NET_CONF} /net\"\n"
        ).expect("failed to write manifest");

        let mut state = CutState{
            cpio_output_arg: None,
            elfs: Gather {
                names: vec!(GatherEnt::NameStatic("ls")),
                off: 0,
            },
            kmods: vec!(),
            data: GatherData {
                items: vec!(),
                off: 0,
            },
            autoruns: 0,
            manifests: Gather {
                names: vec!(GatherEnt::Manifest(tfest.clone())),
                off: 0,
            },
        };
        gather_manifest_entries(&conf, &mut state)
            .expect("failed to parse manifest");

        assert_eq!(
            state.elfs.names,
            vec!(
                GatherEnt::NameStatic("ls"),
                GatherEnt::Name("bash".to_string()),
            )
        );
        assert_eq!(
            state.data.items,
            vec!(GatherItem{
                src: PathBuf::from(conf.get("VM_NET_CONF").unwrap()),
                dst: PathBuf::from("/net"),
                flags: 0,
            })
        );

        // parse again, this time with one unsupported key
        fs::write(&tfest, "unsupported=v\ninstall=mkdir")
            .expect("failed to write manifest");
        state.manifests.off = 0;
        gather_manifest_entries(&conf, &mut state)
            .expect_err("parse bad manifest");
    }
}
