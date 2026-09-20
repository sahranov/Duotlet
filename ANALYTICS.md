# Download analytics

The [report](https://github.com/sahranov/Duotlet/tree/analytics-data) records public GitHub Release asset counters daily at approximately 06:17 UTC (09:17 Moscow). It includes prereleases. Run [Download analytics](https://github.com/sahranov/Duotlet/actions/workflows/download-analytics.yml) manually to refresh it sooner.

The independent `analytics-data` branch stores the report (`README.md`), complete observations (`history.json`), and per-file export (`downloads.csv`). Data is committed to Git rather than kept in expiring workflow artifacts. The first observation is a lifetime baseline; past daily download history cannot be reconstructed. Subsequent increases span the actual interval between observations. Deleted/replaced assets or decreasing counters produce an unknown increase rather than a misleading negative or zero number. Old observations remain intact.

The headline counts `.dmg` and `.zip` release assets only. Checksums are listed separately. GitHub's automatically generated source archives have no counters in this API. Repeat downloads and automated downloads count too. Download counts do not prove installation or launch, and provide no names, GitHub accounts, email addresses, countries, or download referrers.

[GitHub Traffic](https://github.com/sahranov/Duotlet/graphs/traffic) separately shows repository visitors, clones and referral sites to maintainers over the last 14 days. This workflow does not archive Traffic: its API needs additional repository administration read access that the ordinary Actions token does not provide. No extra token or external analytics service is required for release counters.

The workflow uses a repository-scoped Actions token with `contents: write` to save the report. It never modifies releases or app binaries. GitHub may delay scheduled jobs and may disable schedules in public repositories after 60 days without activity; use the workflow page to check its last successful run and re-enable it when needed. API errors fail the run without saving a new snapshot. A failed push fails the run; the last published report stays intact.

For a local report:

```sh
python3 scripts/download-analytics.py
```

Output goes to `output/download-analytics/`. Public counters work without authentication; `GH_TOKEN` optionally increases API limits. Calculation and failure checks:

```sh
python3 -m unittest discover -s Tests -p 'test_download_analytics.py'
```

App usage is a separate measurement. Existing Duotlet code sends `App.launched` and fixed error categories to TelemetryDeck only after onboarding and with analytics sharing enabled. The download report neither changes that integration nor verifies ownership of its dashboard or signal delivery.

Sources: [GitHub release assets API](https://docs.github.com/en/rest/releases/assets), [repository traffic](https://docs.github.com/en/repositories/viewing-activity-and-data-for-your-repository/viewing-traffic-to-a-repository), [scheduled workflow limitations](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).
