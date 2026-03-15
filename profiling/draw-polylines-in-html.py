#!/usr/bin/env python3

from pathlib import Path
import json
import math
import sys
import pandas as pd


INPUT_CSV = Path("dynamic_monitoring.csv")
OUTPUT_HTML = Path("graph.html")


def guess_unit_strict(col: str) -> str:
    name = col.lower()

    if name.endswith("_pct") or name.endswith("_util"):
        return "%"
    if name.endswith("_mhz"):
        return "MHz"
    if name.endswith("_mb"):
        return "MB"
    if name.endswith("_w"):
        return "W"
    if name.endswith("_c"):
        return "°C"
    if name.endswith("_int"):
        return "Integer"

    raise ValueError(
        f"unrecognized unit suffix for column: {col}. "
        f"expected one of: _pct, _util, _mhz, _mb, _w, _c, _int"
    )


def is_time_col_name(name: str) -> bool:
    s = name.strip().lower()
    return any(token in s for token in ["ts", "time", "timestamp"])


def to_finite_float_strict(v, row_idx: int, col_name: str) -> float:
    if pd.isna(v):
        return 0.0

    try:
        x = float(v)
    except Exception:
        return 0.0

    if math.isnan(x) or math.isinf(x):
        return 0.0

    return x


def infer_time_type(values: list[float]) -> str:
    if all(float(v).is_integer() for v in values):
        return "integer"
    return "float"


def rolling_mean(values: list[float], window: int) -> list[float]:
    if window <= 1:
        return values[:]

    out = []
    half = window // 2

    for i in range(len(values)):
        left = max(0, i - half)
        right = min(len(values), i + half + 1)
        nums = values[left:right]
        out.append(sum(nums) / len(nums))

    return out


def normalize_series(values: list[float], vmin: float, vmax: float) -> list[float]:
    if vmax == vmin:
        return [0.0 for _ in values]

    return [(v - vmin) / (vmax - vmin) for v in values]


def diff_pct_series(values: list[float], vmin: float, vmax: float) -> list[float]:
    if vmax == vmin:
        return [0.0 for _ in values]

    return [(v - vmin) / (vmax - vmin) * 100.0 for v in values]


def fmt_value(v: float, unit: str) -> str:
    return f"{v:.2f} {unit}" if unit else f"{v:.2f}"


def fmt_percent(v: float) -> str:
    return f"{v:.2f}%"


def validate_csv_structure(df: pd.DataFrame) -> tuple[str, list[str]]:
    if len(df.columns) < 2:
        raise ValueError("csv must contain at least 2 columns: 1 time column + 1 metric column")

    time_col = df.columns[0]
    metric_cols = list(df.columns[1:])

    if not is_time_col_name(time_col):
        raise ValueError(
            f"first column does not look like a timestamp column: {time_col}. "
            f"expected name containing ts, time, or timestamp"
        )

    for col in metric_cols:
        guess_unit_strict(col)

    return time_col, metric_cols


def validate_and_convert(df: pd.DataFrame, time_col: str, metric_cols: list[str]) -> tuple[list[float], dict[str, list[float]]]:
    time_values = []
    metric_values = {col: [] for col in metric_cols}

    for row_pos, (_, row) in enumerate(df.iterrows(), start=2):
        ts = to_finite_float_strict(row[time_col], row_pos, time_col)
        time_values.append(ts)

        for col in metric_cols:
            x = to_finite_float_strict(row[col], row_pos, col)
            metric_values[col].append(x)

    if not time_values:
        raise ValueError("csv has no data rows")

    for i in range(1, len(time_values)):
        if time_values[i] <= time_values[i - 1]:
            raise ValueError(
                f"time column is not strictly increasing at data row {i + 2}: "
                f"{time_values[i - 1]} -> {time_values[i]}"
            )

    return time_values, metric_values


def build_report_payload(report_name: str, time_col: str, time_values: list[float], x_sec: list[float], metric_cols: list[str], metric_values: dict[str, list[float]]) -> dict:
    metrics = {}

    for col in metric_cols:
        raw = metric_values[col]
        unit = guess_unit_strict(col)
        smooth = rolling_mean(raw, window=7)
        vmin = min(raw)
        vmax = max(raw)
        avg = sum(raw) / len(raw)

        metrics[col] = {
            "unit": unit,
            "raw": raw,
            "smooth": smooth,
            "norm_raw": normalize_series(raw, vmin, vmax),
            "norm_smooth": normalize_series(smooth, vmin, vmax),
            "avg_label": fmt_value(avg, unit),
            "min_label": fmt_value(vmin, unit),
            "max_label": fmt_value(vmax, unit),
            "hover_raw_text": [fmt_value(v, unit) for v in raw],
            "hover_smooth_text": [fmt_value(v, unit) for v in smooth],
            "hover_diff_text": [fmt_percent(v) for v in diff_pct_series(raw, vmin, vmax)],
            "min": vmin,
            "max": vmax,
        }

    return {
        "report_name": report_name,
        "time_col": time_col,
        "time_type": infer_time_type(time_values),
        "row_count": len(time_values),
        "x_sec": x_sec,
        "metric_cols": metric_cols,
        "metrics": metrics,
    }


def build_html(report_payload: dict) -> str:
    payload_json = json.dumps(report_payload, ensure_ascii=False)
    title = "Dynamic Monitoring Graph"

    html = r'''<!doctype html>
<html lang=en>
<head>
    <meta charset=utf-8>
    <title>__TITLE__</title>
    <script src=https://cdn.plot.ly/plotly-2.35.2.min.js></script>
    <style>
        :root {
            --sidebar-width: 520px;
            --sidebar-min-width: 360px;
            --sidebar-max-width: 900px;
            --panel-bg: #fafafa;
            --panel-border: #d7d7d7;
            --muted: #666;
            --danger: #c62828;
            --success: #17823b;
        }
        * {
            box-sizing: border-box;
        }
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 0;
            overflow: hidden;
        }
        .page {
            display: flex;
            height: 100vh;
            width: 100vw;
        }
        .sidebar {
            width: var(--sidebar-width);
            min-width: var(--sidebar-min-width);
            max-width: var(--sidebar-max-width);
            padding: 14px;
            overflow: auto;
            background: #fff;
        }
        .resizer {
            width: 8px;
            cursor: col-resize;
            background: linear-gradient(to right, #ececec, #d6d6d6, #ececec);
            border-left: 1px solid #d0d0d0;
            border-right: 1px solid #d0d0d0;
            user-select: none;
        }
        .main {
            flex: 1;
            min-width: 0;
            padding: 12px;
        }
        #plot {
            width: 100%;
            height: calc(100vh - 24px);
        }
        .panel {
            border: 1px solid var(--panel-border);
            border-radius: 10px;
            padding: 12px;
            background: var(--panel-bg);
            margin-bottom: 12px;
        }
        .panel-title {
            font-size: 17px;
            font-weight: 700;
            margin-bottom: 10px;
        }
        .sub-title {
            font-weight: 700;
            margin-top: 8px;
            margin-bottom: 5px;
        }
        .row {
            margin-bottom: 8px;
        }
        .toolbar {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            margin-bottom: 10px;
        }
        button, select, input[type=number] {
            font: inherit;
        }
        button:disabled,
        input:disabled,
        select:disabled {
            opacity: 0.45;
            cursor: not-allowed;
        }
        .metric-list {
            display: flex;
            flex-direction: column;
            gap: 10px;
        }
        .group-box {
            border: 1px solid #dedede;
            border-radius: 9px;
            padding: 10px 10px 8px 10px;
            background: #fff;
        }
        .group-title {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 17px;
            font-weight: 700;
            margin-bottom: 8px;
        }
        .group-items {
            border-top: 1px solid #d7d7d7;
            padding-top: 8px;
            display: flex;
            flex-direction: column;
            gap: 6px;
        }
        .metric-item {
            display: flex;
            align-items: flex-start;
            gap: 8px;
            padding: 3px 0;
            transition: opacity 120ms ease-in-out;
        }
        .metric-item.disabled {
            opacity: 0.45;
        }
        .metric-text {
            display: flex;
            flex-direction: column;
            line-height: 1.2;
        }
        .metric-name {
            font-weight: 700;
            word-break: break-all;
        }
        .metric-avg {
            color: var(--muted);
            font-size: 13px;
        }
        .badge {
            display: inline-block;
            margin-left: 6px;
            padding: 1px 6px;
            border: 1px solid #9d9d9d;
            border-radius: 999px;
            font-size: 11px;
            color: #444;
            vertical-align: middle;
        }
        .hint {
            color: var(--muted);
            font-size: 13px;
            margin-top: 6px;
        }
        .status-line {
            font-size: 14px;
            margin-bottom: 8px;
        }
        .status-off {
            color: var(--danger);
            font-weight: 700;
        }
        .status-on {
            color: var(--success);
            font-weight: 700;
        }
        .slider-row {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 4px;
        }
        #comparison_shift {
            flex: 1;
        }
        .zoom-info {
            color: var(--muted);
            font-size: 13px;
            align-self: center;
        }
        .toast {
            position: fixed;
            left: 50%;
            bottom: 28px;
            transform: translateX(-50%);
            background: rgba(40, 40, 40, 0.94);
            color: #fff;
            padding: 10px 16px;
            border-radius: 8px;
            font-size: 14px;
            z-index: 9999;
            display: none;
            box-shadow: 0 8px 24px rgba(0, 0, 0, 0.25);
        }
        .hidden {
            display: none !important;
        }
    </style>
</head>
<body>
    <script id=report-data type=application/json>__PAYLOAD_JSON__</script>
    <div class=page>
        <div class=sidebar id=sidebar>
            <div class=panel>
                <div class=panel-title>Visual style</div>
                <div class=toolbar>
                    <button type=button onclick=resetZoom()>Reset zoom</button>
                    <span class=zoom-info id=zoom_info>Zoom: 100%</span>
                </div>
                <div class=sub-title>Y axis mode</div>
                <div class=row><label><input type=radio name=y_mode value=normalized checked onchange=renderPlot()> Normalized ratio</label></div>
                <div class=row><label><input type=radio name=y_mode value=actual onchange=renderPlot()> Actual value</label></div>
                <div class=row><label><input type=radio name=y_mode value=delta id=y_mode_delta onchange=renderPlot()> Delta view (only available in comparison mode)</label></div>
                <div class=sub-title>Line source</div>
                <div class=row><label><input type=checkbox id=use_smooth checked onchange=rebuildAllDerivedAndRender()> Use smoothed values</label></div>
                <div class=row><label for=window_size>Smoothing window:</label> <input id=window_size type=number min=1 step=2 value=7 onchange=rebuildAllDerivedAndRender() style="width:80px;"></div>
                <div class=hint>Mouse wheel zoom centers on the current hover position. Box zoom only works horizontally.</div>
            </div>

            <div class=panel>
                <div class=panel-title>Comparison</div>
                <div class=status-line id=comparison_status_line>Comparison Mode: <span class=status-off>OFF</span></div>
                <div class=toolbar>
                    <button type=button id=load_second_btn onclick=triggerComparisonLoad()>Load the second report</button>
                    <button type=button id=unload_second_btn onclick=unloadComparisonReport()>Unload the second report</button>
                    <input id=comparison_file type=file accept=.html,text/html style="display:none" onchange=handleComparisonFile(event)>
                </div>
                <div class=sub-title>Align X axis manually</div>
                <div class=slider-row>
                    <input id=comparison_shift type=range min=-10 max=10 value=0 step=1 oninput=handleShiftSliderInput()>
                    <span id=comparison_shift_value>0.0</span>
                </div>
                <div class=hint>Hold Shift while dragging the slider to use finer 0.1-step movement.</div>
                <div class=hint>Comparison requires matching timestamp column name, timestamp type, metric name, and unit.</div>
            </div>

            <div class=panel>
                <div class=panel-title>Attributes</div>
                <div class=toolbar>
                    <button type=button onclick=selectAll()>Select all</button>
                    <button type=button onclick=selectNone()>Select none</button>
                </div>
                <div class=row>
                    <label for=group_mode>Group attributes by:</label>
                    <select id=group_mode onchange=handleGroupModeChange()>
                        <option value=unit selected>Group by unit</option>
                        <option value=name>Group by name</option>
                        <option value=none>No grouping</option>
                    </select>
                </div>
                <div id=metric_list class=metric-list></div>
            </div>
        </div>
        <div class=resizer id=sidebar_resizer></div>
        <div class=main><div id=plot></div></div>
    </div>
    <div id=toast class=toast></div>
    <script>
        const PRIMARY_REPORT = JSON.parse(document.getElementById("report-data").textContent);
        let SECONDARY_REPORT = null;
        let comparisonShift = 0.0;
        let lastHoverX = null;
        let baseAxisRanges = { x: null, y: null };
        let currentPlotState = { traces: [], comparisonMode: false, yMode: "normalized" };
        let suppressRelayoutHandler = false;
        let toastTimer = null;
        let pendingXRange = null;
        const colorCache = {};
        const selectionState = {};
        const groupState = {};

        function hashString(s) {
            let h = 0;
            for (let i = 0; i < s.length; i++) {
                h = ((h << 5) - h) + s.charCodeAt(i);
                h |= 0;
            }
            return Math.abs(h);
        }
        function getColorForMetric(name) {
            if (!(name in colorCache)) {
                const hue = hashString(name) % 360;
                colorCache[name] = `hsl(${hue}, 70%, 42%)`;
            }
            return colorCache[name];
        }
        function dimColor(color) {
            const m = color.match(/^hsl\((\d+),\s*(\d+)%,\s*(\d+)%\)$/);
            if (!m) {
                return color;
            }
            return `hsla(${m[1]}, ${m[2]}%, ${Math.max(28, Number(m[3]) + 10)}%, 0.72)`;
        }
        function getMetricUnit(report, name) {
            return report.metrics[name].unit || "";
        }
        function getMetricNames(report) {
            return report.metric_cols.filter(name => report.metrics[name]);
        }
        function metricIsComparable(name) {
            return !!(SECONDARY_REPORT && SECONDARY_REPORT.metrics[name] && getMetricUnit(PRIMARY_REPORT, name) === getMetricUnit(SECONDARY_REPORT, name));
        }
        function getComparableMetricNames() {
            return getMetricNames(PRIMARY_REPORT).filter(metricIsComparable);
        }
        function getGroupMode() {
            return document.getElementById("group_mode").value;
        }
        function getNameGroupKey(name) {
            const idx = name.indexOf("_");
            return idx >= 0 ? name.slice(0, idx) : name;
        }
        function getMetricGroupInfo(name) {
            const mode = getGroupMode();
            if (mode === "unit") {
                const unit = getMetricUnit(PRIMARY_REPORT, name) || "(no unit)";
                return { mode: mode, key: unit, label: `Unit: ${unit}` };
            }
            if (mode === "name") {
                const prefix = getNameGroupKey(name);
                return { mode: mode, key: prefix, label: `Name: ${prefix}` };
            }
            return { mode: mode, key: name, label: name };
        }
        function getStateGroupKey(mode, key) {
            return `${mode}::${key}`;
        }
        function getSortedGroupKeys() {
            const items = new Map();
            for (const name of getMetricNames(PRIMARY_REPORT)) {
                const info = getMetricGroupInfo(name);
                if (!items.has(info.key)) {
                    items.set(info.key, info);
                }
            }
            return Array.from(items.values()).sort((a, b) => a.key.localeCompare(b.key));
        }
        function getMetricsInGroup(groupInfo) {
            return getMetricNames(PRIMARY_REPORT).filter(name => getMetricGroupInfo(name).key === groupInfo.key);
        }
        function ensureStateDefaults() {
            for (const name of getMetricNames(PRIMARY_REPORT)) {
                if (!(name in selectionState)) {
                    selectionState[name] = true;
                }
            }
            for (const groupInfo of getSortedGroupKeys()) {
                const stateKey = getStateGroupKey(groupInfo.mode, groupInfo.key);
                if (!(stateKey in groupState)) {
                    groupState[stateKey] = true;
                }
            }
        }
        function saveStateFromDom() {
            for (const cb of document.querySelectorAll('#metric_list input[data-metric-name]')) {
                selectionState[cb.dataset.metricName] = cb.checked;
            }
            for (const cb of document.querySelectorAll('#metric_list input[data-state-group-key]')) {
                groupState[cb.dataset.stateGroupKey] = cb.checked;
            }
        }
        function applyGroupStateToSelection(groupInfo) {
            const stateKey = getStateGroupKey(groupInfo.mode, groupInfo.key);
            const checked = !!groupState[stateKey];
            for (const name of getMetricsInGroup(groupInfo)) {
                selectionState[name] = checked;
            }
        }
        function updateGroupStateFromSelection(groupInfo) {
            const names = getMetricsInGroup(groupInfo);
            const stateKey = getStateGroupKey(groupInfo.mode, groupInfo.key);
            groupState[stateKey] = names.length > 0 && names.every(name => !!selectionState[name]);
        }
        function handleGroupModeChange() {
            saveStateFromDom();
            ensureStateDefaults();
            buildMetricList();
            renderPlot();
        }
        function buildMetricItem(name, groupInfo) {
            const row = document.createElement("label");
            row.className = "metric-item";
            const cb = document.createElement("input");
            cb.type = "checkbox";
            cb.checked = !!selectionState[name];
            cb.dataset.metricName = name;
            cb.onchange = () => {
                selectionState[name] = cb.checked;
                if (groupInfo) {
                    updateGroupStateFromSelection(groupInfo);
                }
                buildMetricList();
                renderPlot();
            };
            const textWrap = document.createElement("span");
            textWrap.className = "metric-text";
            const nameSpan = document.createElement("span");
            nameSpan.className = "metric-name";
            nameSpan.style.color = selectionState[name] ? getColorForMetric(name) : "#8a8a8a";
            nameSpan.textContent = name;
            if (metricIsComparable(name)) {
                const badge = document.createElement("span");
                badge.className = "badge";
                badge.textContent = "comparable";
                nameSpan.appendChild(badge);
            }
            const meta = PRIMARY_REPORT.metrics[name];
            const avgSpan = document.createElement("span");
            avgSpan.className = "metric-avg";
            avgSpan.textContent = `avg=${meta.avg_label}   min=${meta.min_label}   max=${meta.max_label}`;
            if (!selectionState[name]) {
                row.classList.add("disabled");
            }
            textWrap.appendChild(nameSpan);
            textWrap.appendChild(avgSpan);
            row.appendChild(cb);
            row.appendChild(textWrap);
            return row;
        }
        function buildMetricList() {
            ensureStateDefaults();
            const root = document.getElementById("metric_list");
            root.innerHTML = "";
            const mode = getGroupMode();
            if (mode === "none") {
                const box = document.createElement("div");
                box.className = "group-box";
                const title = document.createElement("div");
                title.className = "group-title";
                title.textContent = "All attributes";
                box.appendChild(title);
                const items = document.createElement("div");
                items.className = "group-items";
                for (const name of getMetricNames(PRIMARY_REPORT)) {
                    items.appendChild(buildMetricItem(name, null));
                }
                box.appendChild(items);
                root.appendChild(box);
                return;
            }
            for (const groupInfo of getSortedGroupKeys()) {
                const stateKey = getStateGroupKey(groupInfo.mode, groupInfo.key);
                const box = document.createElement("div");
                box.className = "group-box";
                const header = document.createElement("label");
                header.className = "group-title";
                const groupCb = document.createElement("input");
                groupCb.type = "checkbox";
                groupCb.checked = !!groupState[stateKey];
                groupCb.dataset.stateGroupKey = stateKey;
                groupCb.onchange = () => {
                    groupState[stateKey] = groupCb.checked;
                    applyGroupStateToSelection(groupInfo);
                    buildMetricList();
                    renderPlot();
                };
                const label = document.createElement("span");
                label.textContent = groupInfo.label;
                header.appendChild(groupCb);
                header.appendChild(label);
                box.appendChild(header);
                const items = document.createElement("div");
                items.className = "group-items";
                for (const name of getMetricsInGroup(groupInfo)) {
                    items.appendChild(buildMetricItem(name, groupInfo));
                }
                box.appendChild(items);
                root.appendChild(box);
            }
        }
        function getSelectedMetrics() {
            return getMetricNames(PRIMARY_REPORT).filter(name => !!selectionState[name]);
        }
        function selectAll() {
            for (const groupInfo of getSortedGroupKeys()) {
                groupState[getStateGroupKey(groupInfo.mode, groupInfo.key)] = true;
            }
            for (const name of getMetricNames(PRIMARY_REPORT)) {
                selectionState[name] = true;
            }
            buildMetricList();
            renderPlot();
        }
        function selectNone() {
            for (const groupInfo of getSortedGroupKeys()) {
                groupState[getStateGroupKey(groupInfo.mode, groupInfo.key)] = false;
            }
            for (const name of getMetricNames(PRIMARY_REPORT)) {
                selectionState[name] = false;
            }
            buildMetricList();
            renderPlot();
        }
        function getYMode() {
            const node = document.querySelector('input[name="y_mode"]:checked');
            return node ? node.value : "normalized";
        }
        function getDisplayUnit(unit) {
            return unit === "" ? "Integer" : unit;
        }
        function getSharedVisibleUnit(selected) {
            const units = selected.map(name => unitMap[name]);
            if (units.length === 0) {
                return null;
            }

            const first = units[0];
            if (units.every(unit => unit === first)) {
                return first;
            }

            return null;
        }
        function setYMode(mode) {
            const node = document.querySelector(`input[name="y_mode"][value="${mode}"]`);
            if (node) {
                node.checked = true;
            }
        }
        function updateYModeUi() {
            const deltaNode = document.getElementById("y_mode_delta");
            const enabled = !!SECONDARY_REPORT;
            deltaNode.disabled = !enabled;
            if (!enabled && getYMode() === "delta") {
                setYMode("normalized");
            }
        }
        function getUseSmooth() {
            return document.getElementById("use_smooth").checked;
        }
        function getSmoothingWindow() {
            const input = document.getElementById("window_size");
            let window = parseInt(input.value, 10);
            if (!Number.isFinite(window) || window < 1) {
                window = 1;
            }
            if (window % 2 === 0) {
                window += 1;
            }
            input.value = String(window);
            return window;
        }
        function rollingMean(arr, window) {
            if (window <= 1) {
                return arr.slice();
            }
            const out = [];
            const half = Math.floor(window / 2);
            for (let i = 0; i < arr.length; i++) {
                const left = Math.max(0, i - half);
                const right = Math.min(arr.length, i + half + 1);
                let sum = 0;
                let count = 0;
                for (let j = left; j < right; j++) {
                    sum += arr[j];
                    count++;
                }
                out.push(sum / count);
            }
            return out;
        }
        function normalizeSeries(arr, minVal, maxVal) {
            if (maxVal === minVal) {
                return arr.map(() => 0.0);
            }
            return arr.map(v => (v - minVal) / (maxVal - minVal));
        }
        function diffPctSeries(arr, minVal, maxVal) {
            if (maxVal === minVal) {
                return arr.map(() => "0.00%");
            }
            return arr.map(v => `${(((v - minVal) / (maxVal - minVal)) * 100).toFixed(2)}%`);
        }
        function fmtValue(v, unit) {
            const s = Number(v).toFixed(2);
            return unit ? `${s} ${unit}` : s;
        }
        function rebuildDerivedForReport(report, window) {
            for (const name of getMetricNames(report)) {
                const metric = report.metrics[name];
                const smooth = rollingMean(metric.raw, window);
                metric.smooth = smooth;
                metric.norm_raw = normalizeSeries(metric.raw, metric.min, metric.max);
                metric.norm_smooth = normalizeSeries(smooth, metric.min, metric.max);
                metric.hover_smooth_text = smooth.map(v => fmtValue(v, metric.unit || ""));
                metric.hover_diff_text = diffPctSeries(metric.raw, metric.min, metric.max);
            }
        }
        function rebuildAllDerivedAndRender() {
            const window = getSmoothingWindow();
            rebuildDerivedForReport(PRIMARY_REPORT, window);
            if (SECONDARY_REPORT) {
                rebuildDerivedForReport(SECONDARY_REPORT, window);
            }
            renderPlot();
        }
        function getSeriesForMetric(report, name) {
            const metric = report.metrics[name];
            const yMode = getYMode();
            if (yMode === "normalized") {
                return getUseSmooth() ? metric.norm_smooth : metric.norm_raw;
            }
            return getUseSmooth() ? metric.smooth : metric.raw;
        }
        function comparisonTimestampCompatible(primaryReport, secondaryReport) {
            return primaryReport.time_col === secondaryReport.time_col && primaryReport.time_type === secondaryReport.time_type;
        }
        function updateComparisonUi() {
            const status = document.getElementById("comparison_status_line");
            const loadBtn = document.getElementById("load_second_btn");
            const unloadBtn = document.getElementById("unload_second_btn");
            const slider = document.getElementById("comparison_shift");
            const sliderVal = document.getElementById("comparison_shift_value");
            if (!SECONDARY_REPORT) {
                status.innerHTML = 'Comparison Mode: <span class="status-off">OFF</span>';
                loadBtn.disabled = false;
                unloadBtn.disabled = true;
                slider.disabled = true;
                slider.value = "0";
                sliderVal.textContent = "0.0";
            } else {
                status.innerHTML = 'Comparison Mode: <span class="status-on">ON</span>';
                loadBtn.disabled = true;
                unloadBtn.disabled = false;
                slider.disabled = false;
            }
            updateYModeUi();
            updateComparisonShiftUi();
        }
        function triggerComparisonLoad() {
            if (!SECONDARY_REPORT) {
                document.getElementById("comparison_file").click();
            }
        }
        function showToast(message) {
            const node = document.getElementById("toast");
            node.textContent = message;
            node.style.display = "block";
            if (toastTimer) {
                clearTimeout(toastTimer);
            }
            toastTimer = setTimeout(() => {
                node.style.display = "none";
            }, 3000);
        }
        async function handleComparisonFile(event) {
            const file = event.target.files && event.target.files[0];
            if (!file) {
                return;
            }
            try {
                saveStateFromDom();
                const text = await file.text();
                const parser = new DOMParser();
                const doc = parser.parseFromString(text, "text/html");
                const node = doc.getElementById("report-data");
                if (!node) {
                    throw new Error("selected HTML does not contain embedded report-data");
                }
                const report = JSON.parse(node.textContent);
                if (!comparisonTimestampCompatible(PRIMARY_REPORT, report)) {
                    throw new Error("the second report timestamp column name or timestamp type does not match the first report");
                }
                SECONDARY_REPORT = report;
                comparisonShift = 0.0;
                updateComparisonUi();
                ensureStateDefaults();
                buildMetricList();
                rebuildAllDerivedAndRender();
            } catch (err) {
                SECONDARY_REPORT = null;
                comparisonShift = 0.0;
                updateComparisonUi();
                buildMetricList();
                renderPlot();
                alert(`Failed to load the second report: ${err.message}`);
            } finally {
                event.target.value = "";
            }
        }
        function unloadComparisonReport() {
            if (!SECONDARY_REPORT) {
                return;
            }
            saveStateFromDom();
            SECONDARY_REPORT = null;
            comparisonShift = 0.0;
            updateComparisonUi();
            buildMetricList();
            renderPlot();
        }
        function getComparisonCommonLength() {
            return SECONDARY_REPORT ? Math.min(PRIMARY_REPORT.row_count, SECONDARY_REPORT.row_count) : 0;
        }
        function buildPrimaryIndex(len) {
            return Array.from({ length: len }, (_, i) => i + 1);
        }
        function buildSecondaryIndex(len) {
            return Array.from({ length: len }, (_, i) => i + 1 + comparisonShift);
        }
        function getComparisonSlice(series) {
            return series.slice(0, getComparisonCommonLength());
        }
        function createStandardTrace(name, x, y, custom, role) {
            return {
                x: x,
                y: y,
                mode: "lines",
                type: "scatter",
                name: role === "secondary" ? `${name} [second]` : name,
                line: { color: getColorForMetric(name), dash: role === "secondary" ? "dot" : "solid", width: 2 },
                customdata: custom,
                hovertemplate:
                    "metric=%{fullData.name}<br>" +
                    "source=%{customdata[5]}<br>" +
                    "sample_index=%{customdata[7]}<br>" +
                    (currentPlotState.comparisonMode ? "x_position=%{x:.2f}<br>" : (`time_col=${PRIMARY_REPORT.time_col}<br>time=%{x:.3f} s<br>`)) +
                    (currentPlotState.yMode === "normalized" ? "normalized=%{y:.4f}<br>" : "actual_y=%{y:.4f}<br>") +
                    "raw=%{customdata[0]}<br>" +
                    "smoothed=%{customdata[1]}<br>" +
                    "min=%{customdata[2]}<br>" +
                    "max=%{customdata[3]}<br>" +
                    "diff=%{customdata[4]}<br>" +
                    "unit=%{customdata[6]}<extra></extra>",
            };
        }
        function buildStandardMetricTrace(report, name, role) {
            const metric = report.metrics[name];
            let y = getSeriesForMetric(report, name);
            let x = report.x_sec;
            let custom = [];
            if (currentPlotState.comparisonMode) {
                y = getComparisonSlice(y);
                const rawText = getComparisonSlice(metric.hover_raw_text);
                const smoothText = getComparisonSlice(metric.hover_smooth_text);
                const diffText = getComparisonSlice(metric.hover_diff_text);
                const len = y.length;
                const index = buildPrimaryIndex(len);
                x = role === "secondary" ? buildSecondaryIndex(len) : index;
                custom = index.map((idx, i) => [rawText[i], smoothText[i], metric.min_label, metric.max_label, diffText[i], report.report_name || (role === "secondary" ? "second" : "first"), metric.unit || "", idx]);
            } else {
                custom = report.x_sec.map((_, i) => [metric.hover_raw_text[i], metric.hover_smooth_text[i], metric.min_label, metric.max_label, metric.hover_diff_text[i], report.report_name || "first", metric.unit || "", i + 1]);
            }
            return createStandardTrace(name, x, y, custom, role);
        }
        function buildDeltaTraces(name) {
            const aMetric = PRIMARY_REPORT.metrics[name];
            const bMetric = SECONDARY_REPORT.metrics[name];
            const aSeries = getComparisonSlice(getSeriesForMetric(PRIMARY_REPORT, name));
            const bSeries = getComparisonSlice(getSeriesForMetric(SECONDARY_REPORT, name));
            const len = Math.min(aSeries.length, bSeries.length);
            const x = buildPrimaryIndex(len);
            const posY = [];
            const negY = [];
            const color = getColorForMetric(name);
            const dimmed = dimColor(color);
            const custom = [];
            for (let i = 0; i < len; i++) {
                const delta = bSeries[i] - aSeries[i];
                posY.push(delta >= 0 ? delta : null);
                negY.push(delta < 0 ? delta : null);
                custom.push([
                    aMetric.hover_raw_text[i],
                    bMetric.hover_raw_text[i],
                    aMetric.hover_smooth_text[i],
                    bMetric.hover_smooth_text[i],
                    aMetric.unit || "",
                    delta,
                    i + 1,
                ]);
            }
            const baseHover =
                "metric=%{fullData.name}<br>" +
                "sample_index=%{customdata[6]}<br>" +
                "A raw=%{customdata[0]}<br>" +
                "B raw=%{customdata[1]}<br>" +
                "A smoothed=%{customdata[2]}<br>" +
                "B smoothed=%{customdata[3]}<br>" +
                "delta=%{customdata[5]:.4f} %{customdata[4]}<extra></extra>";
            return [
                {
                    x: x,
                    y: posY,
                    mode: "lines",
                    type: "scatter",
                    name: `${name} [delta]`,
                    line: { color: color, dash: "solid", width: 2.5 },
                    customdata: custom,
                    hovertemplate: baseHover,
                },
                {
                    x: x,
                    y: negY,
                    mode: "lines",
                    type: "scatter",
                    name: `${name} [delta]`,
                    line: { color: dimmed, dash: "dot", width: 2.5 },
                    customdata: custom,
                    hovertemplate: baseHover,
                    showlegend: false,
                },
            ];
        }
        function getVisibleYRangeFromTraces(traces, xRange) {
            const vals = [];
            for (const trace of traces) {
                for (let i = 0; i < trace.x.length; i++) {
                    const x = trace.x[i];
                    const y = trace.y[i];
                    if (y === null || y === undefined || Number.isNaN(y)) {
                        continue;
                    }
                    if (xRange && (x < xRange[0] || x > xRange[1])) {
                        continue;
                    }
                    vals.push(y);
                }
            }
            if (vals.length === 0) {
                return currentPlotState.yMode === "delta" ? { min: -1, max: 1 } : { min: 0, max: 1 };
            }
            let ymin = Math.min(...vals);
            let ymax = Math.max(...vals);
            if (currentPlotState.yMode === "delta") {
                const absMax = Math.max(Math.abs(ymin), Math.abs(ymax));
                const pad = absMax === 0 ? 1 : absMax * 0.08;
                return { min: -(absMax + pad), max: absMax + pad };
            }
            if (ymin === ymax) {
                const pad = ymin === 0 ? 1 : Math.abs(ymin) * 0.05;
                ymin -= pad;
                ymax += pad;
            } else {
                const pad = (ymax - ymin) * 0.05;
                ymin -= pad;
                ymax += pad;
            }
            return { min: ymin, max: ymax };
        }
        function getVisibleUnits(selected, yMode) {
            if (yMode === "normalized" || yMode === "delta") {
                return [];
            }
            const units = [];
            for (const name of selected) {
                units.push(getMetricUnit(PRIMARY_REPORT, name));
                if (currentPlotState.comparisonMode && metricIsComparable(name)) {
                    units.push(getMetricUnit(SECONDARY_REPORT, name));
                }
            }
            return units.filter(Boolean);
        }
        function getYAxisTitle(selected, yMode) {
            if (yMode === "normalized") {
                return "Normalized ratio";
            }
            if (yMode === "delta") {
                const comparable = selected.filter(metricIsComparable);
                const units = comparable.map(name => getMetricUnit(PRIMARY_REPORT, name)).filter(Boolean);
                if (units.length > 0 && units.every(unit => unit === units[0])) {
                    return `Delta value (${units[0]})`;
                }
                return "Delta value";
            }
            const units = getVisibleUnits(selected, yMode);
            if (units.length > 0 && units.every(unit => unit === units[0])) {
                return `Actual value (${units[0]})`;
            }
            return "Actual value";
        }
        function updateComparisonShiftUi() {
            const slider = document.getElementById("comparison_shift");
            const valueNode = document.getElementById("comparison_shift_value");
            if (!SECONDARY_REPORT) {
                slider.value = "0";
                valueNode.textContent = "0.0";
                return;
            }
            const len = getComparisonCommonLength();
            const limit = Math.max(10, len);
            slider.min = String(-limit);
            slider.max = String(limit);
            slider.value = String(comparisonShift);
            valueNode.textContent = Number(comparisonShift).toFixed(1);
        }
        function updateZoomInfo() {
            const node = document.getElementById("zoom_info");
            const plot = document.getElementById("plot");
            if (!baseAxisRanges.x || !plot.layout || !plot.layout.xaxis || !Array.isArray(plot.layout.xaxis.range)) {
                node.textContent = "Zoom: 100%";
                return;
            }
            const baseSpan = Number(baseAxisRanges.x[1]) - Number(baseAxisRanges.x[0]);
            const curSpan = Number(plot.layout.xaxis.range[1]) - Number(plot.layout.xaxis.range[0]);
            if (!(baseSpan > 0) || !(curSpan > 0)) {
                node.textContent = "Zoom: 100%";
                return;
            }
            node.textContent = `Zoom: ${((curSpan / baseSpan) * 100).toFixed(1)}%`;
        }
        function getCurrentTracesForSelected(selected) {
            const traces = [];
            const yMode = getYMode();
            currentPlotState.comparisonMode = !!SECONDARY_REPORT;
            currentPlotState.yMode = yMode;
            if (yMode === "delta") {
                for (const name of selected) {
                    if (metricIsComparable(name)) {
                        traces.push(...buildDeltaTraces(name));
                    }
                }
                return traces;
            }
            for (const name of selected) {
                traces.push(buildStandardMetricTrace(PRIMARY_REPORT, name, "primary"));
                if (currentPlotState.comparisonMode && metricIsComparable(name)) {
                    traces.push(buildStandardMetricTrace(SECONDARY_REPORT, name, "secondary"));
                }
            }
            return traces;
        }
        function computeInitialRanges(traces) {
            let xMin = 0;
            let xMax = 1;
            const xs = [];
            for (const trace of traces) {
                for (const x of trace.x) {
                    if (x !== null && x !== undefined && !Number.isNaN(x)) {
                        xs.push(x);
                    }
                }
            }
            if (xs.length > 0) {
                xMin = Math.min(...xs);
                xMax = Math.max(...xs);
                if (xMin === xMax) {
                    xMin -= 1;
                    xMax += 1;
                }
            }
            const yRange = getVisibleYRangeFromTraces(traces, [xMin, xMax]);
            return { x: [xMin, xMax], y: [yRange.min, yRange.max] };
        }
        function getPointCountInRange(traces, xRange) {
            const idxs = new Set();
            for (const trace of traces) {
                for (let i = 0; i < trace.x.length; i++) {
                    const x = trace.x[i];
                    const y = trace.y[i];
                    if (y === null || y === undefined || Number.isNaN(y)) {
                        continue;
                    }
                    if (x >= xRange[0] && x <= xRange[1]) {
                        idxs.add(`${trace.name}:${i}`);
                    }
                }
            }
            return idxs.size;
        }
        function applyRanges(xRange, yRange) {
            const plot = document.getElementById("plot");
            suppressRelayoutHandler = true;
            Plotly.relayout(plot, {
                "xaxis.range": [xRange[0], xRange[1]],
                "yaxis.range": [yRange[0], yRange[1]],
            }).then(() => {
                suppressRelayoutHandler = false;
                updateZoomInfo();
            });
        }
        function resetZoom() {
            if (!baseAxisRanges.x || !baseAxisRanges.y) {
                return;
            }
            applyRanges(baseAxisRanges.x, baseAxisRanges.y);
        }
        function handleShiftSliderInput() {
            comparisonShift = parseFloat(document.getElementById("comparison_shift").value) || 0.0;
            document.getElementById("comparison_shift_value").textContent = comparisonShift.toFixed(1);
            renderPlot();
        }
        function installShiftSensitiveSliderStep() {
            const slider = document.getElementById("comparison_shift");
            window.addEventListener("keydown", event => {
                if (event.key === "Shift") {
                    slider.step = "0.1";
                }
            });
            window.addEventListener("keyup", event => {
                if (event.key === "Shift") {
                    slider.step = "1";
                }
            });
            window.addEventListener("blur", () => {
                slider.step = "1";
            });
        }
        function installResizer() {
            const resizer = document.getElementById("sidebar_resizer");
            const sidebar = document.getElementById("sidebar");
            let active = false;
            resizer.addEventListener("mousedown", event => {
                active = true;
                document.body.style.cursor = "col-resize";
                event.preventDefault();
            });
            window.addEventListener("mousemove", event => {
                if (!active) {
                    return;
                }
                const minW = 360;
                const maxW = Math.min(window.innerWidth - 220, 900);
                const w = Math.max(minW, Math.min(maxW, event.clientX));
                sidebar.style.width = `${w}px`;
            });
            window.addEventListener("mouseup", () => {
                if (active) {
                    active = false;
                    document.body.style.cursor = "";
                }
            });
        }
        function installPlotInteractions() {
            const plot = document.getElementById("plot");
            if (!plot || plot.dataset.interactionsInstalled === "1" || typeof plot.on !== "function") {
                return;
            }
            plot.on("plotly_hover", event => {
                if (event && event.points && event.points.length > 0) {
                    const x = event.points[0].x;
                    if (typeof x === "number" && Number.isFinite(x)) {
                        lastHoverX = x;
                    }
                }
            });
            plot.on("plotly_unhover", () => {
                lastHoverX = null;
            });
            plot.on("plotly_relayout", event => {
                if (suppressRelayoutHandler) {
                    return;
                }
                if (!event || (!("xaxis.range[0]" in event) && !(event.xaxis && event.xaxis.range))) {
                    updateZoomInfo();
                    return;
                }
                let x0;
                let x1;
                if ("xaxis.range[0]" in event && "xaxis.range[1]" in event) {
                    x0 = Number(event["xaxis.range[0]"]);
                    x1 = Number(event["xaxis.range[1]"]);
                } else if (event.xaxis && Array.isArray(event.xaxis.range)) {
                    x0 = Number(event.xaxis.range[0]);
                    x1 = Number(event.xaxis.range[1]);
                }
                if (!Number.isFinite(x0) || !Number.isFinite(x1)) {
                    updateZoomInfo();
                    return;
                }
                const xRange = [Math.min(x0, x1), Math.max(x0, x1)];
                const pointCount = getPointCountInRange(currentPlotState.traces, xRange);
                if (pointCount < 3) {
                    showToast("Zoom range rejected: a valid canvas must contain at least 3 data points.");
                    resetZoom();
                    return;
                }
                const yRange = getVisibleYRangeFromTraces(currentPlotState.traces, xRange);
                applyRanges(xRange, [yRange.min, yRange.max]);
            });
            plot.addEventListener("wheel", event => {
                if (!plot.layout || !plot.layout.xaxis || !Array.isArray(plot.layout.xaxis.range)) {
                    return;
                }
                event.preventDefault();
                const xRange = plot.layout.xaxis.range;
                const x0 = Number(xRange[0]);
                const x1 = Number(xRange[1]);
                if (!Number.isFinite(x0) || !Number.isFinite(x1) || x1 <= x0) {
                    return;
                }
                const anchorX = Number.isFinite(lastHoverX) ? lastHoverX : ((x0 + x1) / 2);
                const factor = event.deltaY < 0 ? 0.85 : (1 / 0.85);
                const newX0 = anchorX - (anchorX - x0) * factor;
                const newX1 = anchorX + (x1 - anchorX) * factor;
                const pointCount = getPointCountInRange(currentPlotState.traces, [newX0, newX1]);
                if (pointCount < 3) {
                    showToast("Zoom range rejected: a valid canvas must contain at least 3 data points.");
                    return;
                }
                const yRange = getVisibleYRangeFromTraces(currentPlotState.traces, [newX0, newX1]);
                applyRanges([newX0, newX1], [yRange.min, yRange.max]);
            }, { passive: false });
            plot.dataset.interactionsInstalled = "1";
        }
        function renderPlot() {
            const selected = getSelectedMetrics();
            const traces = getCurrentTracesForSelected(selected);
            currentPlotState.traces = traces;
            baseAxisRanges = computeInitialRanges(traces);
            const yMode = getYMode();
            const shapes = [];
            if (yMode === "delta") {
                shapes.push({
                    type: "line",
                    xref: "paper",
                    x0: 0,
                    x1: 1,
                    yref: "y",
                    y0: 0,
                    y1: 0,
                    line: { color: "#c62828", width: 3 },
                });
            }
            const layout = {
                title: "Dynamic Monitoring Metrics",
                dragmode: "zoom",
                xaxis: {
                    title: currentPlotState.comparisonMode ? "Sample index" : `Time since start from ${PRIMARY_REPORT.time_col} (sec)`,
                    range: [baseAxisRanges.x[0], baseAxisRanges.x[1]],
                    fixedrange: false,
                },
                yaxis: {
                    title: getYAxisTitle(selected, yMode),
                    range: [baseAxisRanges.y[0], baseAxisRanges.y[1]],
                    fixedrange: true,
                },
                shapes: shapes,
                hovermode: "closest",
                legend: { orientation: "h" },
                margin: { l: 70, r: 25, t: 55, b: 70 },
            };
            Plotly.react("plot", traces, layout, {
                responsive: true,
                displaylogo: false,
                scrollZoom: false,
                doubleClick: false,
            }).then(() => {
                installPlotInteractions();
                updateZoomInfo();
            });
        }
        buildMetricList();
        updateComparisonUi();
        installShiftSensitiveSliderStep();
        installResizer();
        rebuildAllDerivedAndRender();
    </script>
</body>
</html>
'''
    html = html.replace("__TITLE__", title)
    html = html.replace("__PAYLOAD_JSON__", payload_json)
    return html


def main():
    df = pd.read_csv(
        INPUT_CSV,
        keep_default_na=True,
        na_values=["", "N/A", "n/a", "NA", "null", "None"],
    )

    time_col, metric_cols = validate_csv_structure(df)
    time_values, metric_values = validate_and_convert(df, time_col, metric_cols)

    start_ts = time_values[0]
    x_sec = [(v - start_ts) / 1000.0 for v in time_values]

    report_payload = build_report_payload(
        report_name=INPUT_CSV.name,
        time_col=time_col,
        time_values=time_values,
        x_sec=x_sec,
        metric_cols=metric_cols,
        metric_values=metric_values,
    )

    html = build_html(report_payload)
    OUTPUT_HTML.write_text(html, encoding="utf-8")


if __name__ == "__main__":
    csv_files = [Path(arg).resolve() for arg in sys.argv[1:]]
    if not csv_files:
        csv_files = sorted(Path.cwd().glob("*.csv"))

    if not csv_files:
        print(f"no .csv files found in {Path.cwd()}", file=sys.stderr)
        raise SystemExit(1)

    for csv_file in csv_files:
        if csv_file.is_file():
            INPUT_CSV = csv_file
            OUTPUT_HTML = INPUT_CSV.with_suffix(".html")
            try:
                main()
                print(f"generated: {OUTPUT_HTML}")
            except Exception as e:
                print(e)
                print(f"error: failed to generate html from {csv_file}")
        else:
            print(f"error: file not found: {csv_file}", file=sys.stderr)
