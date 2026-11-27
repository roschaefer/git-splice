//! The two forms of a command's help: `--help` prints its usage text, the
//! full reference; `-h` prints a summary derived from it, as Git does.

/// The summary `-h` prints: the SYNOPSIS lines as `usage:` lines, then each
/// option of OPTIONS with the first sentence of its description.
pub fn concise(usage: &str) -> String {
    let command = usage
        .lines()
        .skip_while(|line| *line != "NAME")
        .nth(1)
        .and_then(|line| line.split_whitespace().next())
        .map(|name| name.replacen("git-splice-", "git splice ", 1))
        .unwrap_or_else(|| "git splice".to_string());
    let mut out = String::new();
    for (index, line) in section(usage, "SYNOPSIS").iter().enumerate() {
        let prefix = if index == 0 { "usage: " } else { "   or: " };
        out.push_str(&format!("{prefix}{}\n", line.trim_start()));
    }
    let options = option_summaries(&section(usage, "OPTIONS"));
    if !options.is_empty() {
        out.push('\n');
        out.push_str(&options);
    }
    out.push_str(&format!(
        "\n'{command} --help' prints the full reference.\n"
    ));
    out
}

/// The lines of the section under <heading>, up to the next heading.
fn section<'a>(usage: &'a str, heading: &str) -> Vec<&'a str> {
    usage
        .lines()
        .skip_while(|line| *line != heading)
        .skip(1)
        .take_while(|line| line.is_empty() || line.starts_with(' '))
        .filter(|line| !line.trim().is_empty())
        .collect()
}

/// Each option line, followed by its description up to the end of the
/// first sentence. Links are left out.
fn option_summaries(options: &[&str]) -> String {
    let mut out = String::new();
    let mut in_first_sentence = false;
    for line in options {
        if line.trim_start().starts_with("See also: ") {
            continue;
        }
        if !line.starts_with("     ") {
            out.push_str(line);
            out.push('\n');
            in_first_sentence = true;
        } else if in_first_sentence {
            match first_sentence_end(line) {
                Some(end) => {
                    out.push_str(&line[..end]);
                    in_first_sentence = false;
                }
                None => out.push_str(line),
            }
            out.push('\n');
        }
    }
    out
}

/// Where the sentence that ends in <line> ends, after its full stop.
fn first_sentence_end(line: &str) -> Option<usize> {
    line.match_indices('.')
        .map(|(index, _)| index)
        .find(|&index| {
            let word = line[..index].rsplit(' ').next().unwrap_or("");
            let after = &line[index + 1..];
            (after.is_empty() || after.starts_with(' '))
                && !matches!(word, "e.g" | "i.e" | "etc")
                && !word.ends_with('.')
        })
        .map(|index| index + 1)
}

#[cfg(test)]
mod tests {
    use super::*;

    const USAGE: &str = "\
NAME
    git-splice-x - Do x

SYNOPSIS
    git splice x [--one] <path>
    git splice x --two <path>

DESCRIPTION
    Does x. In detail.

    See also: https://git-splice.roschaefer.de/docs/command-reference/x/#description

OPTIONS
    --one
        Does one, e.g. for 'git splice y'. Then
        more about it.

        See also: https://git-splice.roschaefer.de/docs/command-reference/x/#--one

    --two
        Does two
        on two lines; see 'git splice
        x --help'.

        A second paragraph.

    See also: https://git-splice.roschaefer.de/docs/command-reference/x/#options

MORE
    Details.
";

    #[test]
    fn concise_help_is_the_synopsis_and_each_options_first_sentence() {
        assert_eq!(
            concise(USAGE),
            "\
usage: git splice x [--one] <path>
   or: git splice x --two <path>

    --one
        Does one, e.g. for 'git splice y'.
    --two
        Does two
        on two lines; see 'git splice
        x --help'.

'git splice x --help' prints the full reference.
"
        );
    }

    #[test]
    fn concise_help_of_a_command_without_options_is_its_synopsis() {
        let usage = "NAME\n    git-splice-x - Do x\n\nSYNOPSIS\n    git splice x <path>\n\nDESCRIPTION\n    Does x.\n";
        assert_eq!(
            concise(usage),
            "usage: git splice x <path>\n\n'git splice x --help' prints the full reference.\n"
        );
    }

    #[test]
    fn a_full_stop_inside_a_word_or_an_ellipsis_does_not_end_the_sentence() {
        let line = "    uses .splice and a.b, then ... ends. More.";
        assert_eq!(
            &line[..first_sentence_end(line).unwrap()],
            "    uses .splice and a.b, then ... ends."
        );
        assert_eq!(first_sentence_end("    i.e. not yet"), None);
    }
}
