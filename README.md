# Pingstack Heartbeat

Know when a scheduled GitHub Actions workflow fails or stops running.

Add this action as the last step of a scheduled job. Each run reports to a
[Pingstack](https://pingstack.io) heartbeat check:

- **The job succeeds:** the check stays up.
- **The job fails:** Pingstack alerts right away, with a link to the run.
- **The run never happens** (a disabled schedule, a delayed or skipped run):
  Pingstack alerts when the next report is overdue.

Pingstack is free for 15 checks, and alerts go to email, Slack, Microsoft
Teams, webhooks and more.

## Setup

1. **Create a heartbeat check** in Pingstack with a **Cron** schedule that
   matches your workflow's `cron`, in UTC (or the schedule's `timezone`).
   Give it a grace period of 30 to 60 minutes, since GitHub can start
   scheduled runs late.
2. **Save its ping URL as a secret.** In the repository's **Settings ›
   Secrets and variables › Actions**, add `PINGSTACK_PING_URL`.
3. **Add the step** at the end of the job:

```yaml
name: Nightly export

on:
  schedule:
    - cron: '0 2 * * *'
  workflow_dispatch:

jobs:
  export:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/export.sh

      - name: Report to Pingstack
        if: always()
        uses: pingstack-io/heartbeat-action@v1
        with:
          ping-url: ${{ secrets.PINGSTACK_PING_URL }}
```

`if: always()` matters: without it, the step is skipped when the job fails,
and Pingstack only hears about it once the run is overdue.

Run the workflow once by hand (**Actions › Run workflow**) and check that the
heartbeat arrives in Pingstack.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `ping-url` | required | The check's ping URL. Always pass it from a secret. |
| `status` | `${{ job.status }}` | `success` reports a run; `failure` reports a failure; `cancelled` and `skipped` send nothing. |
| `value` | | A number to check against the check's warning and critical thresholds, such as rows exported. |
| `message` | run summary | Text stored with the ping. Defaults to the workflow name, run number, result and run link. |
| `retries` | `3` | Retries after a network error, a 429 or a 5xx response, waiting 1, 2, 4… seconds. |
| `timeout` | `10` | Seconds to wait for each request. |
| `fail-on-error` | `false` | Fail the step when the report can't be delivered. Off by default, so monitoring never fails your job. |

| Output | Description |
| --- | --- |
| `http-status` | The HTTP status of the last request, or empty when nothing was sent. |

## Examples

**Report a number.** Alert when a run succeeds but does nothing useful:

```yaml
      - id: export
        run: echo "rows=$(./scripts/export.sh --count)" >> "$GITHUB_OUTPUT"

      - name: Report to Pingstack
        if: always()
        uses: pingstack-io/heartbeat-action@v1
        with:
          ping-url: ${{ secrets.PINGSTACK_PING_URL }}
          value: ${{ steps.export.outputs.rows }}
```

**Several jobs.** Report once, from a final job that needs the others, so one
job's success can't hide another's failure:

```yaml
  report:
    needs: [export, backup]
    if: always()
    runs-on: ubuntu-latest
    steps:
      - uses: pingstack-io/heartbeat-action@v1
        with:
          ping-url: ${{ secrets.PINGSTACK_PING_URL }}
          status: ${{ contains(needs.*.result, 'failure') && 'failure' || contains(needs.*.result, 'cancelled') && 'cancelled' || 'success' }}
```

## Security

The ping URL lets anyone who has it report to your check, so keep it in a
secret. The action masks it in logs, never prints it, and only sends to
`https://` addresses on `pingstack.io`. Forks and pull requests from forks
don't receive repository secrets, so runs there send nothing.

The action is a short bash script using `curl`, with no dependencies. It runs
on Linux, macOS and Windows runners.

## Learn more

- [Monitor a GitHub Actions scheduled workflow](https://docs.pingstack.io/recipes/github-actions/)
- [Heartbeat checks](https://docs.pingstack.io/monitoring/heartbeat/)

## License

MIT
