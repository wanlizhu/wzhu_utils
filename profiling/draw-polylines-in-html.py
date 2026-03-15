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

    raise ValueError(
        f"unrecognized unit suffix for column: {col}. "
        f"expected one of: _pct, _util, _mhz, _mb, _w, _c"
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

    html = r"""<!doctype html>
<html lang=en>
<head>
    <meta charset=utf-8>
    <title>__TITLE__</title>
    <script src=https://cdn.plot.ly/plotly-2.35.2.min.js></script>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 0;
        }
        .page {
            display: flex;
            height: 100vh;
        }
        .sidebar {
            width: 560px;
            border-right: 1px solid #ccc;
            padding: 16px;
            box-sizing: border-box;
            overflow-y: auto;
        }
        .main {
            flex: 1;
            padding: 12px;
            box-sizing: border-box;
        }
        #plot {
            width: 100%;
            height: calc(100vh - 24px);
        }
        .controls {
            margin-bottom: 16px;
        }
        .controls button,
        .controls input {
            margin: 4px 4px 4px 0;
        }
        .hint {
            color: #555;
            font-size: 13px;
            margin-top: 8px;
        }
        .section-title {
            font-weight: 600;
            margin-top: 12px;
            margin-bottom: 6px;
        }
        .metric-list {
            display: flex;
            flex-direction: column;
            gap: 10px;
        }
        .unit-group {
            border: 1px solid #ddd;
            border-radius: 6px;
            padding: 8px;
        }
        .unit-group-header {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 6px;
            font-weight: 600;
        }
        .unit-group-items {
            display: flex;
            flex-direction: column;
            gap: 6px;
        }
        .metric-item {
            display: flex;
            align-items: flex-start;
            gap: 8px;
            padding: 2px 0;
        }
        .metric-text {
            display: flex;
            flex-direction: column;
            line-height: 1.2;
        }
        .metric-name {
            font-weight: 600;
            word-break: break-all;
        }
        .metric-avg {
            color: #555;
            font-size: 13px;
        }
        .badge {
            display: inline-block;
            margin-left: 6px;
            padding: 1px 6px;
            border: 1px solid #999;
            border-radius: 999px;
            font-size: 11px;
            color: #444;
            vertical-align: middle;
        }
        .comparison-status {
            color: #555;
            font-size: 13px;
            margin-top: 4px;
        }
        .slider-row {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-top: 6px;
        }
        #comparison_shift {
            flex: 1;
        }
        .hidden {
            display: none;
        }
    </style>
</head>
<body>
    <script id=report-data type=application/json>__PAYLOAD_JSON__</script>
    <div class=page>
        <div class=sidebar>
            <div class=controls>
                <div>
                    <button type=button onclick=selectAll()>Select all</button>
                    <button type=button onclick=selectNone()>Select none</button>
                </div>
                <div class=section-title>Y axis mode</div>
                <div><label><input type=radio name=y_mode value=normalized checked onchange=renderPlot()> Normalized ratio</label></div>
                <div><label><input type=radio name=y_mode value=actual onchange=renderPlot()> Actual value</label></div>
                <div class=section-title>Line source</div>
                <div><label><input type=checkbox id=use_smooth checked onchange=rebuildAllDerivedAndRender()> Use smoothed values</label></div>
                <div style="margin-top:10px;"><label for=window_size>Smoothing window:</label> <input id=window_size type=number min=1 step=2 value=7 onchange=rebuildAllDerivedAndRender() style="width:80px;"></div>
                <div class=section-title>Attributes</div>
                <div>
                    <button type=button onclick=triggerComparisonLoad()>Load comparison report</button>
                    <button type=button onclick=unloadComparisonReport()>Unload comparison report</button>
                    <input id=comparison_file type=file accept=.html,text/html style="display:none" onchange=handleComparisonFile(event)>
                </div>
                <div id=comparison_status class=comparison-status>No comparison report loaded.</div>
                <div id=comparison_shift_wrap class="hidden">
                    <div class=section-title>Comparison alignment</div>
                    <div class=slider-row>
                        <input id=comparison_shift type=range min=-10 max=10 value=0 step=1 oninput=handleShiftSliderInput()>
                        <span id=comparison_shift_value>0.0</span>
                    </div>
                    <div class=hint>Hold Shift while dragging the slider to use finer 0.1-step movement.</div>
                </div>
                <div class=hint>
                    Comparison mode loads another HTML report generated by this same script.
                    Comparable attributes require the same column name and the same unit, and the comparison report must use the same timestamp column name and timestamp type.
                </div>
            </div>
            <div id=metric_list class=metric-list></div>
        </div>
        <div class=main><div id=plot></div></div>
    </div>
    <script>
        const PRIMARY_REPORT = JSON.parse(document.getElementById("report-data").textContent);
        let SECONDARY_REPORT = null;
        let comparisonShift = 0.0;
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
                colorCache[name] = `hsl(${hue}, 70%, 45%)`;
            }
            return colorCache[name];
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
        function getGroupKey(unit) {
            return unit || "(no unit)";
        }
        function getSortedGroupKeys() {
            const keys = new Set();
            for (const name of getMetricNames(PRIMARY_REPORT)) {
                keys.add(getGroupKey(getMetricUnit(PRIMARY_REPORT, name)));
            }
            return Array.from(keys).sort((a, b) => a.localeCompare(b));
        }
        function getMetricsInGroup(groupKey) {
            return getMetricNames(PRIMARY_REPORT).filter(name => getGroupKey(getMetricUnit(PRIMARY_REPORT, name)) === groupKey);
        }
        function ensureStateDefaults() {
            for (const name of getMetricNames(PRIMARY_REPORT)) {
                if (!(name in selectionState)) {
                    selectionState[name] = true;
                }
            }
            for (const groupKey of getSortedGroupKeys()) {
                if (!(groupKey in groupState)) {
                    groupState[groupKey] = true;
                }
            }
        }
        function saveStateFromDom() {
            for (const cb of document.querySelectorAll('#metric_list input[data-metric-name]')) {
                selectionState[cb.dataset.metricName] = cb.checked;
            }
            for (const cb of document.querySelectorAll('#metric_list input[data-group-key]')) {
                groupState[cb.dataset.groupKey] = cb.checked;
            }
        }
        function applyGroupStateToSelection(groupKey) {
            const checked = !!groupState[groupKey];
            for (const name of getMetricsInGroup(groupKey)) {
                selectionState[name] = checked;
            }
        }
        function updateGroupStateFromSelection(groupKey) {
            const names = getMetricsInGroup(groupKey);
            groupState[groupKey] = names.length > 0 && names.every(name => !!selectionState[name]);
        }
        function buildMetricList() {
            ensureStateDefaults();
            const root = document.getElementById("metric_list");
            root.innerHTML = "";
            for (const groupKey of getSortedGroupKeys()) {
                const groupBox = document.createElement("div");
                groupBox.className = "unit-group";
                const header = document.createElement("label");
                header.className = "unit-group-header";
                const groupCb = document.createElement("input");
                groupCb.type = "checkbox";
                groupCb.checked = !!groupState[groupKey];
                groupCb.dataset.groupKey = groupKey;
                groupCb.onchange = () => {
                    groupState[groupKey] = groupCb.checked;
                    applyGroupStateToSelection(groupKey);
                    buildMetricList();
                    renderPlot();
                };
                const headerText = document.createElement("span");
                headerText.textContent = `Unit: ${groupKey}`;
                header.appendChild(groupCb);
                header.appendChild(headerText);
                groupBox.appendChild(header);
                const items = document.createElement("div");
                items.className = "unit-group-items";
                for (const name of getMetricsInGroup(groupKey)) {
                    const row = document.createElement("label");
                    row.className = "metric-item";
                    const cb = document.createElement("input");
                    cb.type = "checkbox";
                    cb.value = name;
                    cb.checked = !!selectionState[name];
                    cb.dataset.metricName = name;
                    cb.onchange = () => {
                        selectionState[name] = cb.checked;
                        updateGroupStateFromSelection(groupKey);
                        buildMetricList();
                        renderPlot();
                    };
                    const textWrap = document.createElement("span");
                    textWrap.className = "metric-text";
                    const nameSpan = document.createElement("span");
                    nameSpan.className = "metric-name";
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
                    textWrap.appendChild(nameSpan);
                    textWrap.appendChild(avgSpan);
                    row.appendChild(cb);
                    row.appendChild(textWrap);
                    items.appendChild(row);
                }
                groupBox.appendChild(items);
                root.appendChild(groupBox);
            }
        }
        function getSelectedMetrics() {
            return getMetricNames(PRIMARY_REPORT).filter(name => !!selectionState[name]);
        }
        function selectAll() {
            for (const groupKey of getSortedGroupKeys()) {
                groupState[groupKey] = true;
            }
            for (const name of getMetricNames(PRIMARY_REPORT)) {
                selectionState[name] = true;
            }
            buildMetricList();
            renderPlot();
        }
        function selectNone() {
            for (const groupKey of getSortedGroupKeys()) {
                groupState[groupKey] = false;
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
            if (getYMode() === "normalized") {
                return getUseSmooth() ? metric.norm_smooth : metric.norm_raw;
            }
            return getUseSmooth() ? metric.smooth : metric.raw;
        }
        function comparisonTimestampCompatible(primaryReport, secondaryReport) {
            return primaryReport.time_col === secondaryReport.time_col && primaryReport.time_type === secondaryReport.time_type;
        }
        function updateComparisonStatus() {
            const node = document.getElementById("comparison_status");
            if (!SECONDARY_REPORT) {
                node.textContent = "No comparison report loaded.";
                return;
            }
            node.textContent = `Comparison report loaded: ${SECONDARY_REPORT.report_name}. Comparable attributes: ${getComparableMetricNames().length}.`;
        }
        function triggerComparisonLoad() {
            document.getElementById("comparison_file").click();
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
                    throw new Error("comparison report timestamp column name or timestamp type does not match the primary report");
                }
                SECONDARY_REPORT = report;
                comparisonShift = 0.0;
                updateComparisonStatus();
                updateComparisonShiftUi();
                ensureStateDefaults();
                buildMetricList();
                rebuildAllDerivedAndRender();
            } catch (err) {
                SECONDARY_REPORT = null;
                comparisonShift = 0.0;
                updateComparisonStatus();
                updateComparisonShiftUi();
                buildMetricList();
                renderPlot();
                alert(`Failed to load comparison report: ${err.message}`);
            } finally {
                event.target.value = "";
            }
        }
        function unloadComparisonReport() {
            saveStateFromDom();
            SECONDARY_REPORT = null;
            comparisonShift = 0.0;
            updateComparisonStatus();
            updateComparisonShiftUi();
            buildMetricList();
            renderPlot();
        }
        function getComparisonCommonLength() {
            return SECONDARY_REPORT ? Math.min(PRIMARY_REPORT.row_count, SECONDARY_REPORT.row_count) : 0;
        }
        function buildPrimaryX(len) {
            return Array.from({ length: len }, (_, i) => i + 1);
        }
        function buildSecondaryX(len) {
            return Array.from({ length: len }, (_, i) => i + 1 + comparisonShift);
        }
        function getComparisonSlice(series) {
            return series.slice(0, getComparisonCommonLength());
        }
        function buildTrace(report, name, role) {
            const yMode = getYMode();
            const metric = report.metrics[name];
            const color = getColorForMetric(name);
            const comparisonMode = !!SECONDARY_REPORT;
            let y = getSeriesForMetric(report, name);
            let x = report.x_sec;
            let custom = [];
            if (comparisonMode) {
                y = getComparisonSlice(y);
                const rawText = getComparisonSlice(metric.hover_raw_text);
                const smoothText = getComparisonSlice(metric.hover_smooth_text);
                const diffText = getComparisonSlice(metric.hover_diff_text);
                const len = y.length;
                const pointIndex = buildPrimaryX(len);
                x = role === "secondary" ? buildSecondaryX(len) : pointIndex;
                custom = pointIndex.map((idx, i) => [rawText[i], smoothText[i], metric.min_label, metric.max_label, diffText[i], report.report_name || (role === "secondary" ? "comparison" : "primary"), metric.unit || "", idx]);
            } else {
                custom = report.x_sec.map((_, i) => [metric.hover_raw_text[i], metric.hover_smooth_text[i], metric.min_label, metric.max_label, metric.hover_diff_text[i], report.report_name || "primary", metric.unit || "", i + 1]);
            }
            return {
                x: x,
                y: y,
                mode: "lines",
                type: "scatter",
                name: role === "secondary" ? `${name} [comparison]` : name,
                line: { color: color, dash: role === "secondary" ? "dot" : "solid", width: 2 },
                customdata: custom,
                hovertemplate:
                    "metric=%{fullData.name}<br>" +
                    "source=%{customdata[5]}<br>" +
                    "sample_index=%{customdata[7]}<br>" +
                    (comparisonMode ? "x_position=%{x:.2f}<br>" : (`time_col=${report.time_col}<br>time=%{x:.3f} s<br>`)) +
                    (yMode === "normalized" ? "normalized=%{y:.4f}<br>" : "actual_y=%{y:.4f}<br>") +
                    "raw=%{customdata[0]}<br>" +
                    "smoothed=%{customdata[1]}<br>" +
                    "min=%{customdata[2]}<br>" +
                    "max=%{customdata[3]}<br>" +
                    "diff=%{customdata[4]}<br>" +
                    "unit=%{customdata[6]}<extra></extra>",
            };
        }
        function calcVisibleYRange(traces) {
            const vals = [];
            for (const trace of traces) {
                for (const v of trace.y) {
                    if (v !== null && v !== undefined && !Number.isNaN(v)) {
                        vals.push(v);
                    }
                }
            }
            if (vals.length === 0) {
                return { min: 0.0, max: 1.0 };
            }
            let ymin = Math.min(...vals);
            let ymax = Math.max(...vals);
            if (ymin === ymax) {
                const pad = ymin === 0 ? 1.0 : Math.abs(ymin) * 0.05;
                ymin -= pad;
                ymax += pad;
            } else {
                const pad = (ymax - ymin) * 0.05;
                ymin -= pad;
                ymax += pad;
            }
            return { min: ymin, max: ymax };
        }
        function getVisibleUnits(selected) {
            const units = [];
            for (const name of selected) {
                units.push(getMetricUnit(PRIMARY_REPORT, name));
                if (metricIsComparable(name)) {
                    units.push(getMetricUnit(SECONDARY_REPORT, name));
                }
            }
            return units.filter(Boolean);
        }
        function getYAxisTitle(selected) {
            if (getYMode() === "normalized") {
                return "Normalized ratio";
            }
            const units = getVisibleUnits(selected);
            if (units.length === 0) {
                return "Actual value";
            }
            const first = units[0];
            return units.every(unit => unit === first) ? `Actual value (${first})` : "Actual value";
        }
        function updateComparisonShiftUi() {
            const wrap = document.getElementById("comparison_shift_wrap");
            const slider = document.getElementById("comparison_shift");
            const valueNode = document.getElementById("comparison_shift_value");
            if (!SECONDARY_REPORT) {
                wrap.classList.add("hidden");
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
            wrap.classList.remove("hidden");
        }
        function handleShiftSliderInput() {
            const slider = document.getElementById("comparison_shift");
            comparisonShift = parseFloat(slider.value) || 0.0;
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
        function renderPlot() {
            const selected = getSelectedMetrics();
            const traces = [];
            const comparisonMode = !!SECONDARY_REPORT;
            for (const name of selected) {
                traces.push(buildTrace(PRIMARY_REPORT, name, "primary"));
                if (metricIsComparable(name)) {
                    traces.push(buildTrace(SECONDARY_REPORT, name, "secondary"));
                }
            }
            const yRange = calcVisibleYRange(traces);
            const layout = {
                title: "Dynamic Monitoring Metrics",
                xaxis: {
                    title: comparisonMode ? "Sample index" : `Time since start from ${PRIMARY_REPORT.time_col} (sec)`
                },
                yaxis: {
                    title: getYAxisTitle(selected),
                    range: [yRange.min, yRange.max],
                },
                hovermode: "closest",
                legend: { orientation: "h" },
                margin: { l: 60, r: 20, t: 50, b: 60 }
            };
            Plotly.react("plot", traces, layout, { responsive: true, displaylogo: false });
        }
        buildMetricList();
        updateComparisonStatus();
        updateComparisonShiftUi();
        installShiftSensitiveSliderStep();
        rebuildAllDerivedAndRender();
    </script>
</body>
</html>
"""
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
    if len(sys.argv) < 2 or not Path(sys.argv[1]).is_file():
        print(f"usage: {Path(sys.argv[0]).name} <input_csv>", file=sys.stderr)
        raise SystemExit(1)

    INPUT_CSV = Path(sys.argv[1]).resolve()
    OUTPUT_HTML = INPUT_CSV.with_suffix(".html")
    main()
