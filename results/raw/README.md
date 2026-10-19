# Raw evidence

Every number in the report must trace back to the run that produced it. This folder holds those runs locally; Git ignores everything here except this file.

Keep for each attempt:

- the command, stdout, and stderr,
- the result map,
- parameters, environment, Git revision, and input checksums,
- the fields in [experiments/result-fields.txt](../../experiments/result-fields.txt).

Never replace a timeout or failure with zero. Host large evidence publicly with a stable link before submission.
