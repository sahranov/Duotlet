#!/usr/bin/env python3
"""Archive public GitHub release counters; no app telemetry or personal data."""

import argparse
import csv
from datetime import datetime, timezone
import html
import json
import os
from pathlib import Path
import re
from urllib.request import Request, urlopen


def api_list(path, token=None):
    items = []
    page = 1
    while True:
        headers = {"Accept": "application/vnd.github+json",
                   "X-GitHub-Api-Version": "2022-11-28",
                   "User-Agent": "Duotlet-download-analytics"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        request = Request(f"https://api.github.com/{path}?per_page=100&page={page}",
                          headers=headers)
        with urlopen(request, timeout=30) as response:
            batch = json.load(response)
        if not isinstance(batch, list):
            raise ValueError("Expected a GitHub API list")
        items.extend(batch)
        if len(batch) < 100:
            return items
        page += 1


def collect(repo, token=None):
    assets = []
    for release in api_list(f"repos/{repo}/releases", token):
        if release["draft"]:
            continue
        # Fetch all assets separately: the embedded release list may be truncated.
        for asset in api_list(f"repos/{repo}/releases/{release['id']}/assets", token):
            assets.append({"id": asset["id"], "release": release["tag_name"],
                           "name": asset["name"], "downloads": asset["download_count"],
                           "created_at": asset["created_at"],
                           "package": asset["name"].lower().endswith((".dmg", ".zip"))})
    return {"captured_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "assets": sorted(assets, key=lambda asset: asset["id"])}


def increase(current, previous):
    """Unknown for a first observation, removed/reset counters or older new assets."""
    if previous is None:
        return None
    old = {a["id"]: a for a in previous["assets"] if a["package"]}
    new = {a["id"]: a for a in current["assets"] if a["package"]}
    if old.keys() - new.keys():
        return None
    delta = 0
    for asset_id, asset in new.items():
        if asset_id in old:
            value = asset["downloads"] - old[asset_id]["downloads"]
            if value < 0:
                return None
            delta += value
        elif datetime.fromisoformat(asset["created_at"].replace("Z", "+00:00")) >= datetime.fromisoformat(previous["captured_at"]):
            delta += asset["downloads"]
        else:
            return None
    return delta


def total(snapshot):
    return sum(a["downloads"] for a in snapshot["assets"] if a["package"])


def cell(value):
    return html.escape(str(value)).replace("|", "&#124;").replace("\n", " ").replace("\r", " ")


def report(repo, snapshots):
    current = snapshots[-1]
    lines = ["# Duotlet — скачивания", "",
             f"Обновлено: {current['captured_at']} (UTC).", "",
             f"**Скачиваний DMG и ZIP: {total(current)}.**", "",
             "Это скачивания файлов, а не уникальные люди, установки или запуски. "
             "Повторные и тестовые скачивания тоже учитываются. GitHub не раскрывает личности скачавших.", "",
             "## По файлам", "", "| Версия | Файл | Скачивания |", "| --- | --- | ---: |"]
    for asset in current["assets"]:
        lines.append(f"| {cell(asset['release'])} | {cell(asset['name'])} | {asset['downloads']} |")
    if not current["assets"]:
        lines.append("| — | Опубликованных файлов нет | 0 |")
    lines += ["", "Контрольные суммы показаны в таблице, но не входят в итог DMG/ZIP. "
              "Автоматические архивы исходного кода GitHub не входят в этот отчёт.", "",
              "## История наблюдений (последние 60)", "",
              "| Снимок, UTC | DMG + ZIP, всего | Прирост с предыдущего снимка |",
              "| --- | ---: | ---: |"]
    for index in range(max(0, len(snapshots) - 60), len(snapshots)):
        snapshot = snapshots[index]
        delta = increase(snapshot, snapshots[index - 1] if index else None)
        lines.append(f"| {snapshot['captured_at']} | {total(snapshot)} | {'—' if delta is None else '+' + str(delta)} |")
    lines += ["", "«—» означает: нет предыдущего наблюдения либо состав файлов/счётчики "
              "изменились так, что прирост нельзя надёжно посчитать. Первый снимок — накопленный "
              "итог, а не скачивания за этот день. Пропуски запусков означают более длинный интервал.", "",
              "Полная история: [history.json](history.json). Экспорт по файлам: [downloads.csv](downloads.csv). "
              "Удалённые файлы остаются в старых снимках, но не входят в текущий итог.", "",
              f"[Посещения, клоны и источники переходов за 14 дней](https://github.com/{repo}/graphs/traffic) "
              "доступны владельцу в GitHub Traffic; источники относятся к посещениям репозитория, "
              "а не к конкретным скачиваниям.", "",
              f"[Обновить вручную / проверить расписание](https://github.com/{repo}/actions/workflows/download-analytics.yml). "
              "Автообновление запланировано ежедневно на 06:17 UTC; GitHub может задерживать запуск. "
              "В публичных репозиториях расписание может отключиться после 60 дней без активности.", ""]
    return "\n".join(lines)


def save(repo, directory, snapshot):
    history_path = directory / "history.json"
    history = json.loads(history_path.read_text()) if history_path.exists() else {"schema": 1, "repository": repo, "snapshots": []}
    if history["schema"] != 1 or history["repository"] != repo:
        raise ValueError("History schema/repository mismatch")
    snapshots = history["snapshots"]
    if snapshots and snapshot["captured_at"] <= snapshots[-1]["captured_at"]:
        raise ValueError("Snapshot must be newer than existing history")
    snapshots.append(snapshot)
    markdown = report(repo, snapshots)
    directory.mkdir(parents=True, exist_ok=True)
    history_path.write_text(json.dumps(history, ensure_ascii=False, indent=2) + "\n")
    (directory / "README.md").write_text(markdown)
    with (directory / "downloads.csv").open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["captured_at", "asset_id", "release", "file", "downloads", "package"])
        for observation in snapshots:
            for asset in observation["assets"]:
                # Prevent spreadsheet formula execution from repository-controlled names.
                safe = lambda value: "'" + value if value.startswith(("=", "+", "-", "@", "\t", "\r")) else value
                writer.writerow([observation["captured_at"], asset["id"], safe(asset["release"]),
                                 safe(asset["name"]), asset["downloads"], asset["package"]])
    return markdown


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "sahranov/Duotlet"))
    parser.add_argument("--output-dir", type=Path, default=Path("output/download-analytics"))
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
        parser.error("repo must be owner/name")
    # Finish all API reads before writing: an API failure must never create a zero snapshot.
    markdown = save(args.repo, args.output_dir, collect(args.repo, os.environ.get("GH_TOKEN")))
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as handle:
            handle.write(markdown)
    print(f"Saved download report to {args.output_dir / 'README.md'}")


if __name__ == "__main__":
    main()
