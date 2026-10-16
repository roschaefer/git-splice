/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

use std::collections::BTreeMap;
use std::sync::Mutex;
use std::sync::atomic::AtomicBool;
use std::sync::atomic::Ordering;
use std::sync::mpsc;
use std::thread;

use anyhow::Result;

/// Calls `run` for every item, on up to `jobs` threads at the same time, and
/// `apply` for every result, on the calling thread and in the order of the
/// items, as soon as the results of all earlier items have been applied.
///
/// With `jobs` 1, every item runs and is applied before the next one starts.
/// Otherwise the first error, from `run` or `apply`, stops starting further
/// items and is returned once all earlier items are applied, so the items
/// before it are handled as they would be one after another. Items already
/// running finish first, at most `jobs - 1` of them; their results are
/// dropped. A panic in `run` stops starting further items too, and is raised
/// again once the running ones have finished.
pub(crate) fn run_in_parallel<T, R>(
    items: Vec<T>,
    jobs: usize,
    run: impl Fn(T) -> Result<R> + Sync,
    mut apply: impl FnMut(R) -> Result<()>,
) -> Result<()>
where
    T: Send,
    R: Send,
{
    if jobs <= 1 {
        for item in items {
            apply(run(item)?)?;
        }
        return Ok(());
    }

    let threads = jobs.min(items.len());
    let queue = Mutex::new(items.into_iter().enumerate());
    let failed = AtomicBool::new(false);
    thread::scope(|scope| {
        let (sender, receiver) = mpsc::channel();
        for _ in 0..threads {
            let (sender, queue, failed, run) = (sender.clone(), &queue, &failed, &run);
            scope.spawn(move || {
                let _stop_on_panic = StopOnPanic(failed);
                while !failed.load(Ordering::Relaxed) {
                    let Some((index, item)) = queue.lock().expect("queue lock poisoned").next()
                    else {
                        break;
                    };
                    let result = run(item);
                    if result.is_err() {
                        failed.store(true, Ordering::Relaxed);
                    }
                    if sender.send((index, result)).is_err() {
                        break;
                    }
                }
            });
        }
        drop(sender);

        // items are handed out in order, so every item before a failed one
        // has started and its result arrives
        let mut pending = BTreeMap::new();
        let mut next = 0;
        for (index, result) in receiver {
            pending.insert(index, result);
            while let Some(result) = pending.remove(&next) {
                next += 1;
                if let Err(err) = result.and_then(&mut apply) {
                    failed.store(true, Ordering::Relaxed);
                    return Err(err);
                }
            }
        }
        Ok(())
    })
}

/// Sets the flag when the worker thread that holds it unwinds from a panic,
/// so that the other workers stop taking items
struct StopOnPanic<'a>(&'a AtomicBool);

impl Drop for StopOnPanic<'_> {
    fn drop(&mut self) {
        if thread::panicking() {
            self.0.store(true, Ordering::Relaxed);
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::AtomicUsize;
    use std::time::Duration;

    use anyhow::anyhow;

    use super::*;

    #[test]
    fn applies_results_in_the_order_of_the_items_whatever_order_they_finish_in() {
        let mut applied = vec![];
        run_in_parallel(
            vec![30, 0, 20, 10],
            4,
            |millis| {
                thread::sleep(Duration::from_millis(millis));
                Ok(millis)
            },
            |millis| {
                applied.push(millis);
                Ok(())
            },
        )
        .unwrap();
        assert_eq!(applied, vec![30, 0, 20, 10]);
    }

    #[test]
    fn applies_every_item_before_the_next_one_runs_with_one_job() {
        let log = Mutex::new(vec![]);
        run_in_parallel(
            vec![1, 2],
            1,
            |item| {
                log.lock().unwrap().push(format!("run {item}"));
                Ok(item)
            },
            |item| {
                log.lock().unwrap().push(format!("apply {item}"));
                Ok(())
            },
        )
        .unwrap();
        assert_eq!(
            log.into_inner().unwrap(),
            vec!["run 1", "apply 1", "run 2", "apply 2"]
        );
    }

    #[test]
    fn returns_the_first_error_after_applying_the_items_before_it() {
        for jobs in [1, 4] {
            let mut applied = vec![];
            let err = run_in_parallel(
                (0..20).collect(),
                jobs,
                |item| {
                    if item == 5 {
                        Err(anyhow!("item {item} failed"))
                    } else {
                        Ok(item)
                    }
                },
                |item| {
                    applied.push(item);
                    Ok(())
                },
            )
            .unwrap_err();
            assert_eq!(err.to_string(), "item 5 failed");
            assert_eq!(applied, vec![0, 1, 2, 3, 4], "with {jobs} job(s)");
        }
    }

    #[test]
    fn stops_starting_items_when_one_panics() {
        let started = AtomicUsize::new(0);
        let panicked = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            run_in_parallel(
                (0..100).collect(),
                4,
                |item| {
                    started.fetch_add(1, Ordering::Relaxed);
                    if item == 2 {
                        panic!("item {item} panicked");
                    }
                    thread::sleep(Duration::from_millis(10));
                    Ok(item)
                },
                |_| Ok(()),
            )
        }));
        assert!(panicked.is_err());
        let started = started.into_inner();
        assert!(started < 100, "started {started} of 100 items");
    }

    #[test]
    fn stops_at_an_error_from_apply() {
        for jobs in [1, 4] {
            let mut applied = vec![];
            let err = run_in_parallel((0..20).collect(), jobs, Ok, |item| {
                if item == 3 {
                    return Err(anyhow!("applying {item} failed"));
                }
                applied.push(item);
                Ok(())
            })
            .unwrap_err();
            assert_eq!(err.to_string(), "applying 3 failed");
            assert_eq!(applied, vec![0, 1, 2], "with {jobs} job(s)");
        }
    }
}
