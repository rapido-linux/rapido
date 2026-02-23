// SPDX-License-Identifier: (GPL-2.0 OR GPL-3.0)
// Copyright (C) 2021-2025 SUSE S.A.

use std::convert::TryInto;
use std::convert::TryFrom;
use std::fs;
use std::io;
use std::io::prelude::*;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::MetadataExt as UnixMetadataExt;
use std::path::Path;
use std::str;

macro_rules! NEWC_HDR_FMT {
    () => {
        concat!(
            "{magic}{ino:08X}{mode:08X}{uid:08X}{gid:08X}{nlink:08X}",
            "{mtime:08X}{filesize:08X}{major:08X}{minor:08X}{rmajor:08X}",
            "{rminor:08X}{namesize:08X}{chksum:08X}"
        )
    };
}

// Don't print debug messages on release builds...
#[cfg(debug_assertions)]
macro_rules! dout {
    ($($l:tt)*) => { println!($($l)*); }
}
#[cfg(not(debug_assertions))]
macro_rules! dout {
    ($($l:tt)*) => {};
}

pub const NEWC_HDR_LEN: u64 = 110;
pub const PATH_MAX: u64 = 4096;

// format: octal posix mode bits
pub const S_IFIFO: u32 = 0o010000;
pub const S_IFCHR: u32 = 0o020000;
pub const S_IFDIR: u32 = 0o040000;
pub const S_IFBLK: u32 = 0o060000;
pub const S_IFREG: u32 = 0o100000;
pub const S_IFLNK: u32 = 0o120000;
pub const S_IFSOCK: u32 = 0o140000;
pub const S_IFMT: u32 = 0o170000;

pub struct ArchiveProperties {
    // first inode number to use. @ArchiveState.ino increments from this.
    pub initial_ino: u32,
    // if non-zero, then align file data segments to this offset by injecting
    // extra zeros after the filename string terminator.
    pub data_align: u32,
    // When injecting extra zeros into the filename field for data alignment,
    // ensure that it doesn't exceed this size. The linux kernel will ignore
    // files where namesize is larger than PATH_MAX, hence the need for this.
    pub namesize_max: u32,
    // if the archive is being appended to the end of an existing file, then
    // @initial_data_off is used when calculating @data_align alignment.
    pub initial_data_off: u64,
    // mtime, uid and gid to use for archived inodes, instead of the value
    // reported by stat.
    pub fixed_mtime: Option<u32>,
    pub fixed_uid: Option<u32>,
    pub fixed_gid: Option<u32>,
}

impl ArchiveProperties {
    pub fn default() -> ArchiveProperties {
        ArchiveProperties {
            initial_ino: 0, // match GNU cpio numbering
            data_align: 0,
            namesize_max: PATH_MAX as u32,
            initial_data_off: 0,
            fixed_mtime: None,
            fixed_uid: None,
            fixed_gid: None,
        }
    }
}

pub struct ArchiveState {
    // static properties, provided during initialization
    props: ArchiveProperties,
    // offset from the start of this archive
    off: u64,
    // next mapped inode number, used instead of source file inode numbers to
    // ensure reproducibility. Inode numbers all share the same dev (major=0
    // minor=0) namespace.
    ino: u32,
}

impl ArchiveState {
    pub fn new(props: ArchiveProperties) -> ArchiveState {
        ArchiveState {
            off: 0,
            ino: props.initial_ino,
            props,
        }
    }
}

// fs::Metadata is private. This allows callers to explicitly set md
#[derive(PartialEq, Debug)]
pub struct ArchiveMd {
    // ino increments for each cpio entry from props.initial_ino
    // nlink is hardcoded 1 for files, retained for dirs
    pub nlink: u32,
    pub mode: u32,
    // may be overridden by props.fixed_uid/gid/mtime
    pub uid: u32,
    pub gid: u32,
    pub mtime: u32,
    // major and minor hardcoded 0
    pub rmajor: u32,
    pub rminor: u32,
    pub len: u32,
}

impl ArchiveMd {
    pub fn from(state: &ArchiveState, md: &fs::Metadata) -> io::Result<ArchiveMd> {
        let mtime: u32 = match state.props.fixed_mtime {
            Some(t) => t,
            None => match u32::try_from(md.mtime()) {
                // check for 2106 epoch overflow
                Err(_) => return Err(io::Error::new(
                              io::ErrorKind::InvalidInput,
                              "mtime too large for cpio",
                          )),
                Ok(m) => m,
            }
        };

        let mode = md.mode();
        let (nlink, rmajor, rminor) = match mode & S_IFMT {
            // careful, this is confusingly not a bitwise or
            S_IFBLK | S_IFCHR => {
                // Linux kernel uses 32-bit dev_t, encoded as mmmM MMmm. glibc
                // uses 64-bit MMMM Mmmm mmmM MMmm, which is compatible.
                let rd = md.rdev();
                (
                 u32::try_from(md.nlink()).ok(),
                 (((rd >> 32) & 0xfffff000) | ((rd >> 8) & 0x00000fff)) as u32,
                 (((rd >> 12) & 0xffffff00) | (rd & 0x000000ff)) as u32,
                )
            },
            S_IFREG => {
                if md.nlink() > 1 {
                    // For simplicity's sake, hardlinks are archived like
                    // regular files, i.e. they're always assigned a unique
                    // inode number and carry a corresponding data segment (if
                    // present). Use symlinks, or if you really need hardlinks
                    // then create them during init.
                    eprintln!(
                        "(nlink={}) hardlink file data may be duplicated",
                        md.nlink()
                    );
                }
                (Some(1), 0, 0)
            },
            _ => (u32::try_from(md.nlink()).ok(), 0, 0),
        };

        let len = match u32::try_from(md.len()) {
            Err(_) => return Err(io::Error::new(
                          io::ErrorKind::InvalidInput,
                          "file too large for newc",
                      )),
            Ok(l) => l,
        };

        if nlink.is_none() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "nlink too large",
            ));
        }

        Ok(ArchiveMd {
            mode,
            uid: match state.props.fixed_uid {
                Some(u) => u,
                None => md.uid(),
            },
            gid: match state.props.fixed_gid {
                Some(g) => g,
                None => md.gid(),
            },
            nlink: nlink.unwrap(),
            mtime,
            rmajor,
            rminor,
            len,
        })
    }
}

fn path_trim_prefixes(path: &Path) -> io::Result<&[u8]> {
    let outpath = match path.strip_prefix("/") {
        Ok(p) => {
            if p.as_os_str().as_bytes().len() == 0 {
                path // retain '/'
            } else {
                p
            }
        }
        Err(_) => path,
    };

    let fname = match outpath.strip_prefix("./") {
        Ok(p) => {
            let out = p.as_os_str().as_bytes();
            if out.len() == 0 {
                outpath.as_os_str().as_bytes() // retain './' and '.' paths
            } else {
                out
            }
        }
        Err(_) => outpath.as_os_str().as_bytes(),
    };

    if fname.len() + 1 >= PATH_MAX.try_into().unwrap() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "path too long"));
    }

    Ok(fname)
}

pub fn archive_path<W: Seek + Write>(
    state: &mut ArchiveState,
    path: &Path,
    md: &ArchiveMd,
    mut writer: W,
) -> io::Result<()> {
    let fname = path_trim_prefixes(path)?;

    if (md.mode & S_IFMT == S_IFREG && md.len > 0) || md.mode & S_IFMT == S_IFLNK {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "archive_path does not support data files or symlinks",
        ));
    }

    dout!("archiving {} with mode {:o}", path.display(), md.mode);

    write!(
        writer,
        NEWC_HDR_FMT!(),
        magic = "070701",
        ino = {
            let i = state.ino;
            state.ino += 1;
            i
        },
        mode = md.mode,
        uid = md.uid,
        gid = md.gid,
        nlink = md.nlink,
        mtime = md.mtime,
        filesize = 0,
        major = 0,
        minor = 0,
        rmajor = md.rmajor,
        rminor = md.rminor,
        namesize = fname.len() + 1,
        chksum = 0
    )?;
    state.off += NEWC_HDR_LEN;

    writer.write_all(fname)?;
    state.off += fname.len() as u64;

    let mut seek_len: i64 = 1; // fname nulterm
    let padding_len = archive_padlen(state.off + seek_len as u64, 4);
    seek_len += padding_len as i64;
    {
        let z = vec![0u8; seek_len.try_into().unwrap()];
        writer.write_all(&z)?;
    }
    state.off += seek_len as u64;

    Ok(())
}

pub fn archive_symlink<W: Seek + Write>(
    state: &mut ArchiveState,
    path: &Path,
    md: &ArchiveMd,
    symlink_tgt: &Path,
    mut writer: W,
) -> io::Result<()> {
    let fname = path_trim_prefixes(path)?;
    let tgt_bytes = symlink_tgt.as_os_str().as_bytes();
    let datalen: u32 = {
        let d: usize = tgt_bytes.len();
        if d >= PATH_MAX.try_into().unwrap() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "symlink path too long",
            ));
        }
        d.try_into().unwrap()
    };
    // no zero terminator for symlink target path

    if md.mode & S_IFMT != S_IFLNK {
        return Err(io::Error::from(io::ErrorKind::InvalidInput));
    }

    dout!("archiving {} with mode {:o}", path.display(), md.mode);

    write!(
        writer,
        NEWC_HDR_FMT!(),
        magic = "070701",
        ino = {
            let i = state.ino;
            state.ino += 1;
            i
        },
        mode = md.mode,
        uid = md.uid,
        gid = md.gid,
        nlink = md.nlink,
        mtime = md.mtime,
        filesize = datalen,
        major = 0,
        minor = 0,
        rmajor = md.rmajor,
        rminor = md.rminor,
        namesize = fname.len() + 1,
        chksum = 0
    )?;
    state.off += NEWC_HDR_LEN;

    writer.write_all(fname)?;
    state.off += fname.len() as u64;

    let mut seek_len: i64 = 1; // fname nulterm
    let padding_len = archive_padlen(state.off + seek_len as u64, 4);
    seek_len += padding_len as i64;
    {
        let z = vec![0u8; seek_len.try_into().unwrap()];
        writer.write_all(&z)?;
    }
    state.off += seek_len as u64;

    writer.write_all(tgt_bytes)?;
    state.off += u64::from(datalen);
    let dpad_len: usize = archive_padlen(state.off, 4).try_into().unwrap();
    write!(writer, "{pad:.padlen$}", padlen = dpad_len, pad = "\0\0\0")?;
    state.off += dpad_len as u64;

    Ok(())
}

pub fn archive_file<R: Read, W: Seek + Write>(
    state: &mut ArchiveState,
    path: &Path,
    md: &ArchiveMd,
    mut reader: R,
    mut writer: W,
) -> io::Result<()> {
    let fname = path_trim_prefixes(path)?;
    let mut data_align_seek: u32 = 0;

    if md.mode & S_IFMT != S_IFREG {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "not a file"));
    }

    dout!("archiving file {} with mode {:o}", path.display(), md.mode);

    if state.props.data_align > 0 && md.len > state.props.data_align {
        // XXX we're "bending" the newc spec a bit here to inject zeros
        // after fname to provide data segment alignment. These zeros are
        // accounted for in the namesize, but some applications may only
        // expect a single zero-terminator (and 4 byte alignment). GNU cpio
        // and Linux initramfs handle this fine as long as PATH_MAX isn't
        // exceeded.
        data_align_seek = {
            let len: u64 = archive_padlen(
                state.props.initial_data_off + state.off + NEWC_HDR_LEN + fname.len() as u64 + 1,
                u64::from(state.props.data_align),
            );
            let padded_namesize = len + fname.len() as u64 + 1;
            if padded_namesize > u64::from(state.props.namesize_max) {
                dout!(
                    "Suboptimal {} alignment: padded {} > {} namesize maximum",
                    path.display(),
                    padded_namesize,
                    state.props.namesize_max
                );
                0
            } else {
                len.try_into().unwrap()
            }
        };
    }

    write!(
        writer,
        NEWC_HDR_FMT!(),
        magic = "070701",
        ino = {
            let i = state.ino;
            state.ino += 1;
            i
        },
        mode = md.mode,
        uid = md.uid,
        gid = md.gid,
        // see hardlink note in ArchiveMd
        nlink = md.nlink,
        mtime = md.mtime,
        filesize = md.len,
        major = 0,
        minor = 0,
        rmajor = md.rmajor,
        rminor = md.rminor,
        namesize = fname.len() + 1 + data_align_seek as usize,
        chksum = 0
    )?;
    state.off += NEWC_HDR_LEN;

    writer.write_all(fname)?;
    state.off += fname.len() as u64;

    let mut seek_len: i64 = 1; // fname nulterm
    if data_align_seek > 0 {
        seek_len += data_align_seek as i64;
        assert_eq!(archive_padlen(state.off + seek_len as u64, 4), 0);
    } else {
        let padding_len = archive_padlen(state.off + seek_len as u64, 4);
        seek_len += padding_len as i64;
    }
    {
        let z = vec![0u8; seek_len.try_into().unwrap()];
        writer.write_all(&z)?;
    }
    state.off += seek_len as u64;

    // io::copy() can reflink: https://github.com/rust-lang/rust/pull/75272 \o/
    if md.len > 0 {
        let copied = io::copy(&mut reader, &mut writer)?;
        if copied != u64::from(md.len) {
            dout!("copied {}, expected {}", copied, md.len);
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "copy returned unexpected length",
            ));
        }
        state.off += u64::from(md.len);
        let dpad_len: usize = archive_padlen(state.off, 4).try_into().unwrap();
        write!(writer, "{pad:.padlen$}", padlen = dpad_len, pad = "\0\0\0")?;
        state.off += dpad_len as u64;
    }

    Ok(())
}

pub fn archive_padlen(off: u64, alignment: u64) -> u64 {
    (alignment - (off & (alignment - 1))) % alignment
}

pub fn archive_trailer<W: Write>(
    state: &mut ArchiveState,
    mut writer: W
) -> io::Result<u64> {
    const FNAME: &str = "TRAILER!!!";
    const FNAME_LEN: usize = FNAME.len() + 1;

    write!(
        writer,
        NEWC_HDR_FMT!(),
        magic = "070701",
        ino = 0,
        mode = 0,
        uid = 0,
        gid = 0,
        nlink = 1,
        mtime = 0,
        filesize = 0,
        major = 0,
        minor = 0,
        rmajor = 0,
        rminor = 0,
        namesize = FNAME_LEN,
        chksum = 0
    )?;
    state.off += NEWC_HDR_LEN;

    let padding_len = archive_padlen(state.off + FNAME_LEN as u64, 4);
    write!(
        writer,
        "{}\0{pad:.padlen$}",
        FNAME,
        padlen = padding_len as usize,
        pad = "\0\0\0"
    )?;
    state.off += FNAME_LEN as u64 + padding_len as u64;

    Ok(state.off)
}

#[derive(PartialEq, Debug)]
pub struct ArchiveEnt {
    // no ino in ArchiveMd. Could place here if needed.
    pub md: ArchiveMd,
    // namesize includes the nul-term
    pub namesize: u32,
    pub name: [u8; (PATH_MAX + 1) as usize],
    // add &name[0 .. namesize] slice here, or leave it up to caller?
}

impl ArchiveEnt {
    // panics if not valid utf-8. Check @name beforehand if undesired.
    pub fn name_str(&self) -> &str {
        let s = str::from_utf8(&self.name[0 .. (self.namesize as usize) - 1])
            .unwrap();
        // data alignment optimization may leave trailing zeros. strip them...
        match s.split_once('\0') {
            None => s,
            Some((stripped, _)) => stripped,
        }
    }
}

pub struct ArchiveWalker<R: Seek + Read> {
    reader: R,
}

pub fn archive_walk<R: Seek + Read>(
    reader: R,
) -> io::Result<ArchiveWalker<R>> {
    // kernel extraction skips zeros until header. we don't.
    Ok(ArchiveWalker{
        reader,
    })
}

fn archive_read_newc_md(hdr_md: &[u8]) -> io::Result<(ArchiveMd, u32)> {
    // 8 hex chars per field.
    let mut md_iter = hdr_md.chunks_exact(8).map(|f| {
        if let Ok(s) = str::from_utf8(f) {
            if let Ok(u) = u32::from_str_radix(s, 16) {
                return Ok(u);
            }
        }
        Err(io::Error::new(io::ErrorKind::InvalidData, "invalid hdr field"))
    });

    // unwrap here because successfully read NEWC_HDR_LEN bytes
    let md = ArchiveMd{
        // skip ino
        mode: md_iter.nth(1).unwrap()?,
        uid: md_iter.next().unwrap()?,
        gid: md_iter.next().unwrap()?,
        nlink: md_iter.next().unwrap()?,
        mtime: md_iter.next().unwrap()?,
        len: md_iter.next().unwrap()?,
        // skip major/minor
        rmajor: md_iter.nth(2).unwrap()?,
        rminor: md_iter.next().unwrap()?,
    };
    let namesize = md_iter.next().unwrap()?;
    if namesize == 0 || namesize > (PATH_MAX + 1) as u32 {
        return Err(
            io::Error::new(io::ErrorKind::InvalidData, "invalid namesize")
        );
    }

    Ok((md, namesize))
}

impl<R: Seek + Read> Iterator for ArchiveWalker<R> {
    type Item = io::Result<ArchiveEnt>;
    fn next(&mut self) -> Option<Self::Item> {
        let mut hdr_buf = [0u8; NEWC_HDR_LEN as usize];
        // return None if we hit EOF while reading a hdr
        if let Err(e) = self.reader.read_exact(&mut hdr_buf) {
            return match e.kind() {
                io::ErrorKind::UnexpectedEof => None,
                _ => Some(Err(e)),
            }
        }
        match hdr_buf {
            // we only support newc
            [b'0', b'7', b'0', b'7', b'0', b'1', hdr_md @ ..] => {
                let (md, namesize) = match archive_read_newc_md(&hdr_md) {
                    Err(e) => return Some(Err(e)),
                    Ok((md, ns)) => (md, ns),
                };
                let mut buf = [0u8; (PATH_MAX + 1) as usize];
                let mut fbuf = &mut buf[0 .. namesize as usize];
                if let Err(e) = self.reader.read_exact(&mut fbuf) {
                    return Some(Err(e));
                }

                let npad = archive_padlen(NEWC_HDR_LEN + namesize as u64, 4);
                let dlen = md.len as u64;
                let dpad = archive_padlen(dlen, 4);
                let seeklen: i64 = (npad + dlen + dpad).try_into().unwrap();
                if let Err(e) = self.reader.seek(io::SeekFrom::Current(seeklen)) {
                    return Some(Err(e));
                }
                if &buf[0 .. (namesize as usize) - 1] == b"TRAILER!!!" {
                    // cpio trailer treated the same as EOF
                    return None;
                }
                let ae = ArchiveEnt{
                    md,
                    namesize,
                    name: buf,
                    // provide data offset here, to allow callers to grab it?
                };
                Some(Ok(ae))
            },
            [ _bad_hdr @ .. ] => {
                return Some(Err(
                    io::Error::new(io::ErrorKind::InvalidInput, "invalid newc hdr")
                ));
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Seek, Write};

    #[test]
    fn test_archive_iter() {
        let mut c = io::Cursor::new(Vec::new());
        let props = ArchiveProperties::default();
        let amd = ArchiveMd{
            nlink: 1,
            mode: S_IFDIR | 0o777,
            uid: 1,
            gid: 2,
            mtime: 3,
            rmajor: 4,
            rminor: 5,
            len: 0,
        };
        let p = Path::new("hello");

        let mut state = ArchiveState::new(props);
        archive_path(&mut state, &p, &amd, &mut c).unwrap();
        archive_trailer(&mut state, &mut c).unwrap();
        c.seek(io::SeekFrom::Start(0)).unwrap();

        let mut aw = archive_walk(c).unwrap();
        let ae = aw.next().unwrap().unwrap();

        assert_eq!(
            ae,
            ArchiveEnt{
                md: amd,
                namesize: ("hello".len() + 1).try_into().unwrap(),
                name: {
                    let mut buf = [0u8; (PATH_MAX + 1) as usize];
                    let mut fbuf = &mut buf[0 .. (PATH_MAX + 1) as usize];
                    fbuf.write_all("hello".as_bytes()).unwrap();
                    buf
                },
            }
        );
        assert_eq!(ae.name_str(), "hello");

        // cpio trailer entry returns None
        assert!(aw.next().is_none());
    }

    #[test]
    fn test_archive_iter_bogus() {
        let mut c = io::Cursor::new(Vec::new());

        // bad magic
        write!(
            c,
            concat!(NEWC_HDR_FMT!(), "{fname}\0"),
            magic = "370701",
            ino = 0,
            mode = 1,
            uid = 2,
            gid = 3,
            nlink = 4,
            mtime = 5,
            filesize = 0,
            major = 6,
            minor = 7,
            rmajor = 8,
            rminor = 9,
            namesize = 2,
            chksum = 0,
            fname = "A",
        ).unwrap();
        // namesize=2 is 4-byte aligned: (110 + 2)
        c.seek(io::SeekFrom::Start(0)).unwrap();
        let mut aw = archive_walk(c).unwrap();
        assert_eq!(
            aw.next().unwrap().unwrap_err().kind(),
            io::ErrorKind::InvalidInput);

        // good magic, corrupt each field with non-hex
        for corrupt_field in 0..12 {
            let mut c = io::Cursor::new(Vec::new());

            write!(
                c,
                concat!(NEWC_HDR_FMT!(), "{fname}\0"),
                magic = "070701",
                ino = 0,
                mode = 1,
                uid = 2,
                gid = 3,
                nlink = 4,
                mtime = 5,
                filesize = 0,
                major = 6,
                minor = 7,
                rmajor = 8,
                rminor = 9,
                namesize = 2,
                chksum = 0,
                fname = "A",
            ).unwrap();
            // namesize=2 is 4-byte aligned: (110 + 2)

            // matches above
            let amd = ArchiveMd{
                mode: 1,
                uid: 2,
                gid: 3,
                nlink: 4,
                mtime: 5,
                rmajor: 8,
                rminor: 9,
                len: 0,
            };

            let corrupt_off: u64 = "070701".len() as u64 + corrupt_field * 8;
            c.seek(io::SeekFrom::Start(corrupt_off)).unwrap();
            write!(c, "not hex").unwrap();

            c.seek(io::SeekFrom::Start(0)).unwrap();
            let mut aw = archive_walk(c).unwrap();
            let ent = aw.next().unwrap();

            // ino, major, minor and chksum are ignored, so won't cause an error
            match corrupt_field  {
                0 | 7 | 8 | 12 => assert_eq!(
                    ent.unwrap(),
                    ArchiveEnt{
                        md: amd,
                        namesize: 2,
                        name: {
                            let mut buf = [0u8; (PATH_MAX + 1) as usize];
                            let mut fbuf = &mut buf[0 .. (PATH_MAX + 1) as usize];
                            fbuf.write_all("A".as_bytes()).unwrap();
                            buf
                        },
                    }
                ),
                _ => assert_eq!(
                    ent.unwrap_err().kind(),
                    io::ErrorKind::InvalidData
                ),
            }
        }

        // no cpio trailer; EOF should result in None
        assert!(aw.next().is_none());
    }

    #[test]
    fn test_archive_path_trim() {
        assert_eq!(
            b"hello",
            path_trim_prefixes(Path::new("hello")).unwrap()
        );
        assert_eq!(
            b"hello",
            path_trim_prefixes(Path::new("./hello")).unwrap()
        );
        assert_eq!(
            b"hello",
            path_trim_prefixes(Path::new("//hello")).unwrap()
        );
        assert_eq!(b"/", path_trim_prefixes(Path::new("/")).unwrap());
        // should prob return a single '/' for this...
        assert_eq!(b"//", path_trim_prefixes(Path::new("//")).unwrap());
    }

    // archive a file with and without data, via archive_file and archive_path
    #[test]
    fn test_archive_file() {
        let mut c = io::Cursor::new(Vec::new());
        let data = b"this is some file data";
        let amd1 = ArchiveMd{
            nlink: 1,
            mode: S_IFREG | 0o777,
            uid: 1,
            gid: 2,
            mtime: 3,
            rmajor: 4,
            rminor: 5,
            len: 0,
        };
        let amd2 = ArchiveMd{
            len: data.len() as u32,
            ..amd1
        };

        let p1 = Path::new("hello");
        let p2 = Path::new("bye");
        let props = ArchiveProperties::default();
        let mut state = ArchiveState::new(props);
        archive_path(&mut state, &p1, &amd1, &mut c).unwrap();
        archive_file(&mut state, &p2, &amd2, io::Cursor::new(data), &mut c).unwrap();
        // archive path should fail for len > 0 files
        assert!(archive_path(&mut state, &p2, &amd2, &mut c).is_err());

        c.seek(io::SeekFrom::Start(0)).unwrap();
        let mut aw = archive_walk(c).unwrap();

        assert_eq!(
            aw.next().unwrap().unwrap(),
            ArchiveEnt{
                md: amd1,
                namesize: (p1.as_os_str().len() + 1).try_into().unwrap(),
                name: {
                    let mut buf = [0u8; (PATH_MAX + 1) as usize];
                    let mut fbuf = &mut buf[0 .. (PATH_MAX + 1) as usize];
                    fbuf.write_all(p1.as_os_str().as_encoded_bytes()).unwrap();
                    buf
                },
            }
        );

        assert_eq!(
            aw.next().unwrap().unwrap(),
            ArchiveEnt{
                md: amd2,
                namesize: (p2.as_os_str().len() + 1).try_into().unwrap(),
                name: {
                    let mut buf = [0u8; (PATH_MAX + 1) as usize];
                    let mut fbuf = &mut buf[0 .. (PATH_MAX + 1) as usize];
                    fbuf.write_all(p2.as_os_str().as_encoded_bytes()).unwrap();
                    buf
                },
            }
        );

        assert!(aw.next().is_none());
    }

    // Similar to above, but check how data segment alignemt affects name_str().
    #[test]
    fn test_archive_file_aligned() {
        let mut c = io::Cursor::new(Vec::new());
        // datalen > 16-byte alignment to trigger name padding
        let data = b"this is some file data";
        let amd1 = ArchiveMd{
            nlink: 1,
            mode: S_IFREG | 0o777,
            uid: 1,
            gid: 2,
            mtime: 3,
            rmajor: 4,
            rminor: 5,
            len: 0,
        };
        let amd2 = ArchiveMd{
            len: data.len() as u32,
            ..amd1
        };

        let p1 = Path::new("hello");
        let p2 = Path::new("bye");
        let props = ArchiveProperties{
            data_align: 16,
            ..ArchiveProperties::default()
        };
        let mut state = ArchiveState::new(props);
        archive_path(&mut state, &p1, &amd1, &mut c).unwrap();
        archive_file(&mut state, &p2, &amd2, io::Cursor::new(data), &mut c).unwrap();
        // archive path should fail for len > 0 files
        assert!(archive_path(&mut state, &p2, &amd2, &mut c).is_err());

        c.seek(io::SeekFrom::Start(0)).unwrap();
        let mut aw = archive_walk(c).unwrap();

        let ae = aw.next().unwrap().unwrap();
        assert_eq!(ae.name_str(), "hello");

        let ae = aw.next().unwrap().unwrap();
        assert_eq!(ae.name_str(), "bye");
        assert!(aw.next().is_none());
    }
}
