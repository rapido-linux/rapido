// SPDX-License-Identifier: (GPL-2.0 OR GPL-3.0)
// Copyright (C) 2025 SUSE LLC
use std::collections::HashMap;
use std::io;

const CONF_LINE_MAX: usize = 1024 * 100;

// substitute ${VAR} strings with values from previously seen keys in @map.
// no support for env var substitution. No callouts via $(), etc.
fn kv_var_sub(block: &str, map: &HashMap<String, String>) -> io::Result<String> {
    // only support {} wrapped variables that we've already encountered
    let mut varblock = block.split_inclusive(&['{', '}']);
    if varblock.next() != Some("{") {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "variables must be wrapped in {} braces",
        ));
    }
    let var = varblock.next();
    if var.is_none() || !var.unwrap().ends_with("}") {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "no closing brace for variable",
        ));
    }
    let key = var.unwrap().strip_suffix("}").unwrap();

    let subbed = match map.get(key) {
        Some(val) => val.clone(),
        None => {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "invalid variable substitution: not seen",
            ))
        }
    };
    //println!("subbed for {}: {}", key, subbed);
    // need to retain anything that comes after the var-closing '}'
    Ok(varblock.next().iter().fold(subbed, |a, b| a + b))
}

// process a single conf line.
// Roughly attempts to work similar to Bash variable assignment.
// Doesn't support multiple assignments on a single line.
// @line: line buffer to process. Processed data removed on return.
// @varmap: hashmap to use for any ${} variable substitution.
// returns: error or processed key-value pair. @line retains unprocessed portions.
fn kv_process(
    line: &mut String,
    varmap: &HashMap<String, String>,
) -> io::Result<Option<(String, String)>> {
    // ignore empty / comment lines
    if line.trim_start() == "" || line.trim_start().starts_with("#") {
        line.clear();
        return Ok(None);
    }

    // split at first '='
    let (key, val) = match line.split_once('=') {
        None => {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "missing ="));
        }
        Some((k, v)) => (k.trim_start(), v),
    };

    if key == "" {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "empty key"));
    }
    if key.contains(&['\\', '/', '\"', '\'', ' ', '\t', '$', '#', '.', '`']) {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "invalid key"));
    }

    #[derive(PartialEq)]
    enum Quoted {
        No,
        Single,
        Double,
    }
    let mut inquote = Quoted::No;
    let mut escape_next = false;
    let mut comment_next = false;
    let mut var_next = false;

    let mut unquoted_val = String::new();
    for mut quoteblock in val.split_inclusive(&['\\', '\"', '\'', ' ', '\t', '$']) {
        if escape_next {
            if quoteblock.starts_with(&['\\', '\"', '\'', ' ', '\t', '$']) {
                // keep as is
            } else if quoteblock.starts_with('\n') && inquote != Quoted::No {
                // multiline
                break;
            } else {
                // bad escape. on bash the \ is kept if quoted, or dropped if not
                return Err(io::Error::new(io::ErrorKind::InvalidInput, quoteblock));
            }
            escape_next = false;
            unquoted_val.push_str(quoteblock);

            if quoteblock.len() != 1 {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "expected escaped char at split boundary",
                ));
            }
            continue;
        }

        // comment after unquoted space is valid, otherwise invalid
        if comment_next {
            assert!(inquote == Quoted::No); // should only get here outside of quotes
            if quoteblock.starts_with("#") {
                // comment
                break;
            } else if quoteblock.trim_start() == "" {
                continue;
            } else {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "unexpected whitespace",
                ));
            }
        }

        let var_got: String;
        if var_next {
            var_got = kv_var_sub(quoteblock, &varmap)?;
            quoteblock = &var_got;
            var_next = false;
        }

        if quoteblock.ends_with("\\") && inquote != Quoted::Single {
            // next special char is escaped, unless single quoted
            escape_next = true;
            unquoted_val.push_str(quoteblock.strip_suffix("\\").unwrap());
        } else if quoteblock.ends_with("\"") {
            let mut strip_sfx = "\"";
            inquote = match inquote {
                Quoted::No => Quoted::Double,
                Quoted::Double => Quoted::No,
                Quoted::Single => {
                    strip_sfx = "";
                    Quoted::Single
                }
            };
            unquoted_val.push_str(quoteblock.strip_suffix(strip_sfx).unwrap());
        } else if quoteblock.ends_with("\'") {
            let mut strip_sfx = "\'";
            inquote = match inquote {
                Quoted::No => Quoted::Single,
                Quoted::Single => Quoted::No,
                Quoted::Double => {
                    strip_sfx = "";
                    Quoted::Double
                }
            };
            unquoted_val.push_str(quoteblock.strip_suffix(strip_sfx).unwrap());
        } else if quoteblock.ends_with(&[' ', '\t']) && inquote == Quoted::No {
            comment_next = true;
            unquoted_val.push_str(quoteblock.strip_suffix(&[' ', '\t']).unwrap());
        } else if quoteblock.ends_with("$") && inquote != Quoted::Single {
            // variable substitution unless single quoted
            var_next = true;
            unquoted_val.push_str(quoteblock.strip_suffix("$").unwrap());
        } else if quoteblock.ends_with("\n") {
            unquoted_val.push_str(quoteblock.strip_suffix("\n").unwrap());
        } else {
            // EOF without newline, unquoted space, single quoted '$'
            unquoted_val.push_str(quoteblock);
        }
    }

    // handle multi-line with possible '\' terminator
    if inquote != Quoted::No {
        // newline and any spaces collapsed into one space, unless escaped within "
        let mut push_space = " ";
        let mut ml = line.trim_end();
        if ml.ends_with("\\") && inquote == Quoted::Double {
            ml = ml.strip_suffix("\\").unwrap();
            let l = ml.len();
            ml = ml.trim_end();
            if l == ml.len() {
                push_space = "";
            }
        }

        *line = ml.to_string();
        line.push_str(push_space);
        return Ok(None);
    }

    let k = key.to_string();
    line.clear();
    Ok(Some((k, unquoted_val)))
}

//
// Example:
// fn main() {
//     let f = File::open("rapido.conf").expect("failed to open conf file");
//     let mut map: HashMap<String, String> = HashMap::new();
//     let _res = kv_conf_process_append(io::BufReader::new(f), &mut map);
// }
pub fn kv_conf_process_append<R: io::BufRead>(
    mut rdr: R,
    map: &mut HashMap<String, String>,
) -> io::Result<()> {
    let mut buffer = String::new();

    for linenum in 1.. {
        match rdr.read_line(&mut buffer) {
            Err(e) => return Err(e),
            Ok(n) if n == 0 => {
                // EOF
                break;
            }
            Ok(n) if n > CONF_LINE_MAX => {
                let msg = format!("line {} too long", linenum);
                return Err(io::Error::new(io::ErrorKind::InvalidInput, msg));
            }
            Ok(_) => {}
        };

        match kv_process(&mut buffer, map) {
            Err(e) => {
                let msg = match e.get_ref() {
                    Some(eref) => format!("line {}: {:?}", linenum, eref),
                    None => format!("error on line {}", linenum),
                };
                return Err(io::Error::new(e.kind(), msg));
            }
            // buffer may be retain unprocessed data for multiline
            Ok(kv) => match kv {
                Some((k, v)) => map.insert(k, v),
                None => None,
            },
        };
    }
    Ok(())
}

// Example:
// fn main() {
//     let f = File::open("rapido.conf").expect("failed to open conf file");
//     let _kv_map = kv_conf_process(io::BufReader::new(f));
// }
pub fn kv_conf_process<R: io::BufRead>(rdr: R) -> io::Result<HashMap<String, String>> {
    let mut map: HashMap<String, String> = HashMap::new();

    kv_conf_process_append(rdr, &mut map)?;

    Ok(map)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simple() {
        let c = io::Cursor::new("key=val");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "val".to_string())])
        );
    }

    #[test]
    fn test_quoted() {
        let c = io::Cursor::new("key=\"val\"");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "val".to_string())])
        );

        let c = io::Cursor::new("key=\"val spaced\"");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "val spaced".to_string())])
        );

        let c = io::Cursor::new("key=\'val spaced\'");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "val spaced".to_string())])
        );

        // XXX intentional bash divergence: don't turn quoted tabs into spaces
        let c = io::Cursor::new("key=\'val\ttabbed\'");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "val\ttabbed".to_string())])
        );

        let c = io::Cursor::new("key=\'qu\"ot\"ed\'");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "qu\"ot\"ed".to_string())])
        );

        let c = io::Cursor::new("key=\"qu\'oted\"");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "qu\'oted".to_string())])
        );
    }

    #[test]
    fn test_comments() {
        let c = io::Cursor::new("# this is a comment\nkey=val\n #key=newval");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "val".to_string())])
        );

        let c = io::Cursor::new("key=val # this is a trailing comment");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "val".to_string())])
        );

        let c = io::Cursor::new("key=val  # this is a trailing comment ");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "val".to_string())])
        );

        let c = io::Cursor::new("key=val\t\t# this is a trailing comment ");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "val".to_string())])
        );
    }

    #[test]
    fn test_multiple() {
        let c = io::Cursor::new("key=val\nnextkey=nextval");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([
                ("key".to_string(), "val".to_string()),
                ("nextkey".to_string(), "nextval".to_string()),
            ])
        );
    }

    #[test]
    fn test_overwrite() {
        let c = io::Cursor::new("key=val\nkey=newval");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "newval".to_string())])
        );
    }

    #[test]
    fn test_var() {
        let c = io::Cursor::new("k=val\nnextk=${k}");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([
                ("k".to_string(), "val".to_string()),
                ("nextk".to_string(), "val".to_string()),
            ])
        );

        let c = io::Cursor::new("k=val\nnextk=abc${k}def");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([
                ("k".to_string(), "val".to_string()),
                ("nextk".to_string(), "abcvaldef".to_string()),
            ])
        );

        let c = io::Cursor::new("k=val\nnextk=abc\"${k}\"def");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([
                ("k".to_string(), "val".to_string()),
                ("nextk".to_string(), "abcvaldef".to_string()),
            ])
        );

        let c = io::Cursor::new("k=val\nnextk=123\nfink=a${k}b${nextk}c");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([
                ("k".to_string(), "val".to_string()),
                ("nextk".to_string(), "123".to_string()),
                ("fink".to_string(), "avalb123c".to_string()),
            ])
        );

        let c = io::Cursor::new("k=val\nnextk=abc\'${k}\'def");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([
                ("k".to_string(), "val".to_string()),
                ("nextk".to_string(), "abc${k}def".to_string()),
            ])
        );
    }

    #[test]
    fn test_escaped() {
        let c = io::Cursor::new("key=val\\ spaced");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "val spaced".to_string())])
        );
        let c = io::Cursor::new("key=val\\ #spaced\t");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "val #spaced".to_string())])
        );
        let c = io::Cursor::new("key=val\\\ttabbed     ");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "val\ttabbed".to_string())])
        );

        let c = io::Cursor::new("key=val\\\\");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "val\\".to_string())])
        );
    }

    #[test]
    fn test_multiline_kv() {
        // multiline only works with quoting, with or without trailing \
        let c = io::Cursor::new("key=\"line1 \\\nline2\"");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "line1 line2".to_string())])
        );

        let c = io::Cursor::new("key=\"line1   \nline2\"");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "line1 line2".to_string())])
        );

        let c = io::Cursor::new("key=\"line1\\\nline2\"");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "line1line2".to_string())])
        );

        let c = io::Cursor::new("key=\'line1\\\nline2\'");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "line1\\ line2".to_string())])
        );

        let c = io::Cursor::new("key=\'line1\\  \nline2\'");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "line1\\ line2".to_string())])
        );

        let c = io::Cursor::new("key=\"line1\nline2\"");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "line1 line2".to_string())])
        );
    }

    #[test]
    fn test_bad_key() {
        let c = io::Cursor::new("ke/y=val");
        assert!(kv_conf_process(c).is_err());
        let c = io::Cursor::new("ke$y=val");
        assert!(kv_conf_process(c).is_err());
        let c = io::Cursor::new("key =val");
        assert!(kv_conf_process(c).is_err());
        let c = io::Cursor::new("\"key\"=val");
        assert!(kv_conf_process(c).is_err());
        let c = io::Cursor::new("key#=val");
        assert!(kv_conf_process(c).is_err());
        let c = io::Cursor::new("key.=val");
        assert!(kv_conf_process(c).is_err());
        let c = io::Cursor::new("key`=val");
        assert!(kv_conf_process(c).is_err());
    }

    #[test]
    fn test_empty() {
        let c = io::Cursor::new("key=");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("key".to_string(), "".to_string())])
        );

        let c = io::Cursor::new("");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([])
        );

        let c = io::Cursor::new("\n\n# comment");
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([])
        );

        let c = io::Cursor::new("=");
        assert!(kv_conf_process(c).is_err());
    }

    #[test]
    fn test_limit() {
        let mut vec: Vec<u8> = vec![b'k', b'=', b'v', b' ', b'#'];
        vec.resize(CONF_LINE_MAX - 1, b'#');
        vec.extend_from_slice(&[b'\n']);
        let c = io::Cursor::new(&vec);
        assert_eq!(
            kv_conf_process(c).expect("kv_conf_process failed"),
            HashMap::from([("k".to_string(), "v".to_string())])
        );

        vec.truncate(CONF_LINE_MAX - 1);
        vec.resize(CONF_LINE_MAX + 1, b'#');
        let c = io::Cursor::new(&vec);
        assert!(kv_conf_process(c).is_err());
    }

    #[test]
    fn test_append() {
        let c = io::Cursor::new("key=");
        let mut map = kv_conf_process(c).expect("kv_conf_process failed");
        assert_eq!(map, HashMap::from([("key".to_string(), "".to_string())]));

        map.insert("extra".to_string(), "val".to_string());
        let c = io::Cursor::new("key=overwritten\nnextkey=stuff${extra}");
        kv_conf_process_append(c, &mut map).expect("kv_conf_process_append failed");
        assert_eq!(
            map,
            HashMap::from([
                ("key".to_string(), "overwritten".to_string()),
                ("extra".to_string(), "val".to_string()),
                ("nextkey".to_string(), "stuffval".to_string()),
            ])
        );
    }

    // check that a variable without braces fails with line number in Err
    #[test]
    fn test_err_line() {
        let c = io::Cursor::new("k=val\nnextk=123\nfink=a$k");
        let e = kv_conf_process(c).expect_err("variable without braces passed");
        // we probably shouldn't rely on error fmt output stability
        assert_eq!(
            format!("{:?}", e),
            "Custom { kind: InvalidInput, error: \"line 3: \\\"variables must be wrapped in {} braces\\\"\" }"
        );
    }
}
