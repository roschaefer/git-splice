/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

use std::fmt::Write;
use std::path::Path;

use scrut::escaping::Escaper;
use scrut::output::Output;
use scrut::testcase::TestCase;

/// Prints the test cases of a document with their outputs, in one write, so
/// that documents running at the same time (see `--jobs`) don't mix lines
pub(crate) fn debug_testcases(testcases: &[TestCase], test_file_path: &Path, outputs: &[Output]) {
    let mut out = String::new();
    for (index, testcase) in testcases.iter().enumerate() {
        let _ = writeln!(out, "~~~~~~~~~~~~~~~~~~~");
        let _ = writeln!(out, "@ {}", test_file_path.display());
        let _ = writeln!(out, "# {}", testcase.title);
        let _ = writeln!(out, "$ {}", &testcase.shell_expression);
        if index < outputs.len() {
            let _ = writeln!(out, "-> {}", outputs[index].exit_code);
            let _ = writeln!(
                out,
                "{}",
                outputs[index].to_error_string(&Escaper::default())
            );
        } else {
            let _ = writeln!(out, "- no output -");
        }
        let _ = writeln!(out, "~~~~~~~~~~~~~~~~~~~");
    }
    eprint!("{out}");
}
