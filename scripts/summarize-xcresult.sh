#!/bin/bash
# xcresult からテスト結果の要約（合計 / 成功 / 失敗 / スキップ、失敗テストの位置・メッセージ、ライン カバレッジ）を出す。
#
# 使い方: scripts/summarize-xcresult.sh build/test.xcresult
# - 標準出力に人が読む要約を出す
# - 環境変数 GITHUB_STEP_SUMMARY があれば、同じ内容を Markdown で追記する（GitHub Actions の Summary タブ）
# - 終了コード: 結果が Passed 以外（失敗テストあり、ランナーのクラッシュ等）なら 1、xcresult が無ければ 2、
#   テストが 1 件も実行されていなければ 3（-only-testing の指定ミスやテストプランの誤りを緑にしない）、それ以外は 0
#
# 依存: xcrun xcresulttool（Xcode 同梱）と python3（macOS 同梱）
set -euo pipefail

result_bundle="${1:-build/test.xcresult}"

if [[ ! -d "$result_bundle" ]]; then
  echo "summarize-xcresult: $result_bundle がありません（テストが起動前に失敗した可能性。build/*.log を確認）" >&2
  exit 2
fi

# JSON は一時ファイル経由で渡す（環境変数や引数で渡すと ARG_MAX = 1 MiB を超えたときに python3 が起動できない）
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
xcrun xcresulttool get test-results summary --path "$result_bundle" > "$work_dir/summary.json"
xcrun xcresulttool get test-results tests --path "$result_bundle" > "$work_dir/tests.json"
# カバレッジはテストプランで有効な場合だけ入っている。無ければ空ファイルにして要約側で「取得できず」と出す
xcrun xccov view --report --json "$result_bundle" > "$work_dir/coverage.json" 2>/dev/null || : > "$work_dir/coverage.json"

python3 -I - "$work_dir" "$result_bundle" <<'PY'
import json
import os

import sys

work_dir = sys.argv[1]
bundle = sys.argv[2]


def read_json(name):
    text = open(os.path.join(work_dir, name), encoding="utf-8").read().strip()
    return json.loads(text) if text else None


summary = read_json("summary.json") or {}
tests = read_json("tests.json") or {}

# アプリターゲットのライン カバレッジ（参考値。閾値は設けない）
coverage_line = "カバレッジ: 取得できず（テストプランで無効か、xccov が失敗）"
coverage_md = coverage_line
try:
    coverage = read_json("coverage.json")
except json.JSONDecodeError:
    coverage = None
if isinstance(coverage, dict):
    app_targets = [t for t in coverage.get("targets", []) if t.get("name", "").endswith(".app")]
    target = app_targets[0] if app_targets else coverage
    name = target.get("name", "全体")
    ratio = target.get("lineCoverage", 0.0)
    covered = target.get("coveredLines", 0)
    executable = target.get("executableLines", 0)
    coverage_line = f"ライン カバレッジ: {ratio:.1%}（{name}、{covered}/{executable} 行）"
    coverage_md = f"ライン カバレッジ: **{ratio:.1%}**（`{name}`、{covered}/{executable} 行）"

result = summary.get("result", "unknown")
total = summary.get("totalTestCount", 0)
passed = summary.get("passedTests", 0)
failed = summary.get("failedTests", 0)
skipped = summary.get("skippedTests", 0)
expected_failures = summary.get("expectedFailures", 0)

# 失敗メッセージとソース位置は tests ツリーの "Failure Message" ノードにある
failures = []


def walk(node, ancestors):
    if isinstance(node, dict):
        node_type = node.get("nodeType")
        name = node.get("name", "")
        if node_type == "Failure Message":
            case = next((a for a in reversed(ancestors) if a.get("nodeType") == "Test Case"), None)
            location = node.get("sourceLocation") or {}
            failures.append({
                "test": case.get("nodeIdentifier") or case.get("name") if case else "(unknown)",
                "file": location.get("filePath", ""),
                "line": location.get("lineNumber", ""),
                "message": name.strip(),
            })
        for value in node.values():
            walk(value, ancestors + [node])
    elif isinstance(node, list):
        for value in node:
            walk(value, ancestors)


walk(tests, [])


def short_path(path):
    marker = "/iOSEngineerCodeCheck"
    index = path.find(marker)
    return path[index + 1:] if index >= 0 else path


lines = []
lines.append(f"テスト結果: {result}  合計 {total} / 成功 {passed} / 失敗 {failed} / スキップ {skipped}"
             + (f" / 期待どおりの失敗 {expected_failures}" if expected_failures else ""))
lines.append(coverage_line)
lines.append(f"xcresult: {bundle}（Xcode で開くか `xcrun xcresulttool get test-results tests --path {bundle}`）")
if failures:
    lines.append("")
    lines.append("失敗したテスト:")
    for failure in failures:
        where = f"{short_path(failure['file'])}:{failure['line']}" if failure["file"] else "(位置不明)"
        lines.append(f"- {failure['test']}  @ {where}")
        for message_line in failure["message"].splitlines():
            lines.append(f"    {message_line}")
if total == 0:
    lines.append("")
    lines.append("テストが 1 件も実行されていない。-only-testing の指定やテストプランの対象を確認する")
print("\n".join(lines))

step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
if step_summary:
    with open(step_summary, "a", encoding="utf-8") as out:
        icon = "✅" if result == "Passed" and total > 0 else "❌"
        out.write(f"## {icon} テスト結果: {result}\n\n")
        out.write("| 合計 | 成功 | 失敗 | スキップ |\n| --- | --- | --- | --- |\n")
        out.write(f"| {total} | {passed} | {failed} | {skipped} |\n\n")
        out.write(coverage_md + "\n\n")
        if total == 0:
            out.write("テストが 1 件も実行されていない。`-only-testing` の指定やテストプランの対象を確認する。\n\n")
        if failures:
            out.write("### 失敗したテスト\n\n| テスト | 位置 | メッセージ |\n| --- | --- | --- |\n")
            for failure in failures:
                where = f"`{short_path(failure['file'])}:{failure['line']}`" if failure["file"] else "-"
                message = failure["message"].replace("|", "\\|").replace("\n", "<br>")
                out.write(f"| `{failure['test']}` | {where} | {message} |\n")
            out.write("\n")
        out.write(f"xcresult はアーティファクト `test-results` に含まれる（`{os.path.basename(bundle)}`）。\n")

if total == 0:
    raise SystemExit(3)
raise SystemExit(0 if result == "Passed" and failed == 0 else 1)
PY
