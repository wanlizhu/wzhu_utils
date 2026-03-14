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
        #raise ValueError(f"missing data at row {row_idx}, column {col_name}")
        return 0
    
    try:
        x = float(v)
    except Exception as e:
        #raise ValueError(f"illegal non-numeric data at row {row_idx}, column {col_name}: {v}") from e
        return 0 
    
    if math.isnan(x) or math.isinf(x):
        #raise ValueError(f"illegal non-finite data at row {row_idx}, column {col_name}: {v}")
        return 0 
    
    return x


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


def validate_and_convert(
    df: pd.DataFrame,
    time_col: str,
    metric_cols: list[str],
) -> tuple[list[float], dict[str, list[float]]]:
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


def build_html(
    time_col: str,
    x_sec: list[float],
    metric_cols: list[str],
    raw_series: dict[str, list[float]],
    smooth_series: dict[str, list[float]],
    norm_raw_series: dict[str, list[float]],
    norm_smooth_series: dict[str, list[float]],
    avg_label_map: dict[str, str],
    unit_map: dict[str, str],
    min_label_map: dict[str, str],
    max_label_map: dict[str, str],
    hover_raw_text: dict[str, list[str]],
    hover_smooth_text: dict[str, list[str]],
    hover_diff_text: dict[str, list[str]],
    min_map: dict[str, float],
    max_map: dict[str, float],
) -> str:
    return f"""<!doctype html>
<html lang=en>
<head>
    <meta charset=utf-8>
    <title>Dynamic Monitoring Graph</title>
    <script src=https://cdn.plot.ly/plotly-2.35.2.min.js></script>
    <style>
        body {{
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 0;
        }}

        .page {{
            display: flex;
            height: 100vh;
        }}

        .sidebar {{
            width: 460px;
            border-right: 1px solid #ccc;
            padding: 16px;
            box-sizing: border-box;
            overflow-y: auto;
        }}

        .main {{
            flex: 1;
            padding: 12px;
            box-sizing: border-box;
        }}

        #plot {{
            width: 100%;
            height: calc(100vh - 24px);
        }}

        .controls {{
            margin-bottom: 16px;
        }}

        .controls button,
        .controls input {{
            margin: 4px 4px 4px 0;
        }}

        .metric-list {{
            display: flex;
            flex-direction: column;
            gap: 6px;
        }}

        .metric-item {{
            display: flex;
            align-items: flex-start;
            gap: 8px;
            padding: 4px 0;
        }}

        .metric-text {{
            display: flex;
            flex-direction: column;
            line-height: 1.2;
        }}

        .metric-name {{
            font-weight: 600;
            word-break: break-all;
        }}

        .metric-avg {{
            color: #555;
            font-size: 13px;
        }}

        .hint {{
            color: #555;
            font-size: 13px;
            margin-top: 8px;
        }}

        .section-title {{
            font-weight: 600;
            margin-top: 10px;
            margin-bottom: 4px;
        }}
    </style>
</head>
<body>
    <div class=page>
        <div class=sidebar>
            <div class=controls>
                <div>
                    <button type=button onclick=selectAll()>Select all</button>
                    <button type=button onclick=selectNone()>Select none</button>
                </div>

                <div class=section-title>Y axis mode</div>
                <div>
                    <label>
                        <input type=radio name=y_mode value=normalized checked onchange=renderPlot()>
                        Normalized ratio
                    </label>
                </div>
                <div>
                    <label>
                        <input type=radio name=y_mode value=actual onchange=renderPlot()>
                        Actual value
                    </label>
                </div>

                <div class=section-title>Line source</div>
                <div>
                    <label>
                        <input type=checkbox id=use_smooth checked onchange=renderPlot()>
                        Use smoothed values
                    </label>
                </div>

                <div style="margin-top: 10px;">
                    <label for=window_size>Smoothing window:</label>
                    <input id=window_size type=number min=1 step=2 value=7 onchange=rebuildSmooth() style="width:80px;">
                </div>

                <div class=hint>
                    Y axis is rebuilt every time selection or display mode changes, using min/max across all currently selected attributes.
                </div>
            </div>

            <div id=metric_list class=metric-list></div>
        </div>

        <div class=main>
            <div id=plot></div>
        </div>
    </div>

    <script>
        const timeColName = {json.dumps(time_col)};
        const xSec = {json.dumps(x_sec)};
        const rawSeries = {json.dumps(raw_series)};
        let smoothSeries = {json.dumps(smooth_series)};
        let normRawSeries = {json.dumps(norm_raw_series)};
        let normSmoothSeries = {json.dumps(norm_smooth_series)};
        const metricCols = {json.dumps(metric_cols)};
        const avgLabelMap = {json.dumps(avg_label_map)};
        const unitMap = {json.dumps(unit_map)};
        const minLabelMap = {json.dumps(min_label_map)};
        const maxLabelMap = {json.dumps(max_label_map)};
        const hoverRawText = {json.dumps(hover_raw_text)};
        let hoverSmoothText = {json.dumps(hover_smooth_text)};
        let hoverDiffText = {json.dumps(hover_diff_text)};
        const minMap = {json.dumps(min_map)};
        const maxMap = {json.dumps(max_map)};

        function rollingMean(arr, window) {{
            if (window <= 1) {{
                return arr.slice();
            }}

            const out = [];
            const half = Math.floor(window / 2);

            for (let i = 0; i < arr.length; i++) {{
                const left = Math.max(0, i - half);
                const right = Math.min(arr.length, i + half + 1);

                let sum = 0;
                let count = 0;

                for (let j = left; j < right; j++) {{
                    sum += arr[j];
                    count++;
                }}

                out.push(sum / count);
            }}

            return out;
        }}

        function normalizeSeries(arr, minVal, maxVal) {{
            if (maxVal === minVal) {{
                return arr.map(_ => 0.0);
            }}

            return arr.map(v => (v - minVal) / (maxVal - minVal));
        }}

        function diffPctSeries(arr, minVal, maxVal) {{
            if (maxVal === minVal) {{
                return arr.map(_ => "0.00%");
            }}

            return arr.map(v => `${{(((v - minVal) / (maxVal - minVal)) * 100).toFixed(2)}}%`);
        }}

        function fmtValue(v, unit) {{
            const s = Number(v).toFixed(2);
            return unit ? `${{s}} ${{unit}}` : s;
        }}

        function getYMode() {{
            const x = document.querySelector('input[name="y_mode"]:checked');
            return x ? x.value : "normalized";
        }}

        function getSeriesForMetric(name) {{
            const useSmooth = document.getElementById("use_smooth").checked;
            const yMode = getYMode();

            if (yMode === "normalized") {{
                return useSmooth ? normSmoothSeries[name] : normRawSeries[name];
            }}

            return useSmooth ? smoothSeries[name] : rawSeries[name];
        }}

        function calcSelectedYRange(selected) {{
            const vals = [];

            for (const name of selected) {{
                const series = getSeriesForMetric(name);

                for (const v of series) {{
                    vals.push(v);
                }}
            }}

            if (vals.length === 0) {{
                return {{
                    min: 0.0,
                    max: 1.0,
                }};
            }}

            let ymin = Math.min(...vals);
            let ymax = Math.max(...vals);

            if (ymin === ymax) {{
                const pad = ymin === 0 ? 1.0 : Math.abs(ymin) * 0.05;
                ymin -= pad;
                ymax += pad;
            }} else {{
                const pad = (ymax - ymin) * 0.05;
                ymin -= pad;
                ymax += pad;
            }}

            return {{
                min: ymin,
                max: ymax,
            }};
        }}

        function rebuildSmooth() {{
            let window = parseInt(document.getElementById("window_size").value, 10);

            if (!Number.isFinite(window) || window < 1) {{
                window = 1;
            }}

            if (window % 2 === 0) {{
                window += 1;
                document.getElementById("window_size").value = window;
            }}

            hoverSmoothText = {{}};
            hoverDiffText = {{}};
            smoothSeries = {{}};
            normRawSeries = {{}};
            normSmoothSeries = {{}};

            for (const name of metricCols) {{
                const smoothed = rollingMean(rawSeries[name], window);
                const minVal = minMap[name];
                const maxVal = maxMap[name];
                const unit = unitMap[name] || "";

                smoothSeries[name] = smoothed;
                normRawSeries[name] = normalizeSeries(rawSeries[name], minVal, maxVal);
                normSmoothSeries[name] = normalizeSeries(smoothed, minVal, maxVal);
                hoverSmoothText[name] = smoothed.map(v => fmtValue(v, unit));
                hoverDiffText[name] = diffPctSeries(rawSeries[name], minVal, maxVal);
            }}

            renderPlot();
        }}

        function buildMetricList() {{
            const root = document.getElementById("metric_list");
            root.innerHTML = "";

            for (const name of metricCols) {{
                const row = document.createElement("label");
                row.className = "metric-item";

                const cb = document.createElement("input");
                cb.type = "checkbox";
                cb.value = name;
                cb.checked = true;
                cb.onchange = renderPlot;

                const textWrap = document.createElement("span");
                textWrap.className = "metric-text";

                const nameSpan = document.createElement("span");
                nameSpan.className = "metric-name";
                nameSpan.textContent = name;

                const avgSpan = document.createElement("span");
                avgSpan.className = "metric-avg";
                avgSpan.textContent = `avg=${{avgLabelMap[name]}}   min=${{minLabelMap[name]}}   max=${{maxLabelMap[name]}}`;

                textWrap.appendChild(nameSpan);
                textWrap.appendChild(avgSpan);

                row.appendChild(cb);
                row.appendChild(textWrap);
                root.appendChild(row);
            }}
        }}

        function getSelectedMetrics() {{
            return Array.from(document.querySelectorAll('#metric_list input[type="checkbox"]'))
                .filter(x => x.checked)
                .map(x => x.value);
        }}

        function selectAll() {{
            for (const cb of document.querySelectorAll('#metric_list input[type="checkbox"]')) {{
                cb.checked = true;
            }}
            renderPlot();
        }}

        function selectNone() {{
            for (const cb of document.querySelectorAll('#metric_list input[type="checkbox"]')) {{
                cb.checked = false;
            }}
            renderPlot();
        }}

        function buildTrace(name) {{
            const yMode = getYMode();
            const y = getSeriesForMetric(name);
            const custom = xSec.map((_, i) => [
                hoverRawText[name][i],
                hoverSmoothText[name][i],
                minLabelMap[name],
                maxLabelMap[name],
                hoverDiffText[name][i],
            ]);

            return {{
                x: xSec,
                y: y,
                mode: "lines",
                type: "scatter",
                name: name,
                customdata: custom,
                hovertemplate:
                    "metric=%{{fullData.name}}<br>" +
                    "time_col=" + timeColName + "<br>" +
                    "time=%{{x:.3f}} s<br>" +
                    (yMode === "normalized"
                        ? "normalized=%{{y:.4f}}<br>"
                        : "actual_y=%{{y:.4f}}<br>") +
                    "raw=%{{customdata[0]}}<br>" +
                    "smoothed=%{{customdata[1]}}<br>" +
                    "min=%{{customdata[2]}}<br>" +
                    "max=%{{customdata[3]}}<br>" +
                    "diff=%{{customdata[4]}}<extra></extra>",
            }};
        }}

        function renderPlot() {{
            const selected = getSelectedMetrics();
            const yMode = getYMode();
            const traces = selected.map(name => buildTrace(name));
            const yRange = calcSelectedYRange(selected);

            const layout = {{
                title: "Dynamic Monitoring Metrics",
                xaxis: {{
                    title: `Time since start from ${{timeColName}} (sec)`
                }},
                yaxis: {{
                    title: yMode === "normalized" ? "Normalized ratio" : "Actual value",
                    range: [yRange.min, yRange.max],
                }},
                hovermode: "closest",
                legend: {{
                    orientation: "h"
                }},
                margin: {{
                    l: 60,
                    r: 20,
                    t: 50,
                    b: 60
                }}
            }};

            Plotly.react("plot", traces, layout, {{
                responsive: true,
                displaylogo: false
            }});
        }}

        buildMetricList();
        rebuildSmooth();
    </script>
</body>
</html>
"""


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

    raw_series = {}
    smooth_series = {}
    norm_raw_series = {}
    norm_smooth_series = {}
    avg_label_map = {}
    unit_map = {}
    min_label_map = {}
    max_label_map = {}
    hover_raw_text = {}
    hover_smooth_text = {}
    hover_diff_text = {}
    min_map = {}
    max_map = {}

    for col in metric_cols:
        raw = metric_values[col]
        unit = guess_unit_strict(col)
        smooth = rolling_mean(raw, window=7)
        vmin = min(raw)
        vmax = max(raw)
        avg = sum(raw) / len(raw)

        raw_series[col] = raw
        smooth_series[col] = smooth
        norm_raw_series[col] = normalize_series(raw, vmin, vmax)
        norm_smooth_series[col] = normalize_series(smooth, vmin, vmax)
        avg_label_map[col] = fmt_value(avg, unit)
        unit_map[col] = unit
        min_label_map[col] = fmt_value(vmin, unit)
        max_label_map[col] = fmt_value(vmax, unit)
        hover_raw_text[col] = [fmt_value(v, unit) for v in raw]
        hover_smooth_text[col] = [fmt_value(v, unit) for v in smooth]
        hover_diff_text[col] = [fmt_percent(v) for v in diff_pct_series(raw, vmin, vmax)]
        min_map[col] = vmin
        max_map[col] = vmax

    html = build_html(
        time_col=time_col,
        x_sec=x_sec,
        metric_cols=metric_cols,
        raw_series=raw_series,
        smooth_series=smooth_series,
        norm_raw_series=norm_raw_series,
        norm_smooth_series=norm_smooth_series,
        avg_label_map=avg_label_map,
        unit_map=unit_map,
        min_label_map=min_label_map,
        max_label_map=max_label_map,
        hover_raw_text=hover_raw_text,
        hover_smooth_text=hover_smooth_text,
        hover_diff_text=hover_diff_text,
        min_map=min_map,
        max_map=max_map,
    )

    OUTPUT_HTML.write_text(html, encoding="utf-8")
    print(OUTPUT_HTML)


if __name__ == "__main__":
    if len(sys.argv) < 2 or not Path(sys.argv[1]).is_file():
        print(f"usage: {Path(sys.argv[0]).name} <input_csv>", file=sys.stderr)
        raise SystemExit(1)

    INPUT_CSV = Path(sys.argv[1])
    OUTPUT_HTML = INPUT_CSV.with_suffix(".html")

    main()