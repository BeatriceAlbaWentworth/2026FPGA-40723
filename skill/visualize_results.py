
from pathlib import Path
import re
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

# =====================================================
# 1. 项目路径：沿用现有项目，不创建新目录
# =====================================================

ROOT = Path(__file__).resolve().parent

OUTPUT_DIR = ROOT / "outputs"
FPGA_DIR = OUTPUT_DIR / "fpga"
FEATURE_DIR = OUTPUT_DIR / "features"
CLASS_DIR = OUTPUT_DIR / "classification"

# 三种状态的 FPGA 实际回传频谱
SPECTRUM_FILES = {
    "Normal": FPGA_DIR / "normal_001_spectrum.csv",
    "Looseness": FPGA_DIR / "looseness_001_spectrum.csv",
    "Unbalance": FPGA_DIR / "unbalance_001_spectrum.csv",
}

FEATURE_FILE = FEATURE_DIR / "dataset_features.csv"
CONFUSION_FILE = CLASS_DIR / "confusion_matrix.csv"

if not OUTPUT_DIR.exists():
    raise FileNotFoundError(f"找不到输出目录：{OUTPUT_DIR}")

# 中文字体
plt.rcParams["font.sans-serif"] = [
    "Microsoft YaHei", "SimHei", "Arial"
]
plt.rcParams["axes.unicode_minus"] = False


# =====================================================
# 2. 通用工具
# =====================================================

def normalize_name(name):
    return re.sub(r"[^a-z0-9]", "", str(name).lower())


def find_column(df, candidates, keyword=None):
    """自动识别 CSV 中的列名"""

    normalized = {
        normalize_name(c): c for c in df.columns
    }

    for candidate in candidates:
        key = normalize_name(candidate)
        if key in normalized:
            return normalized[key]

    if keyword:
        for col in df.columns:
            name = normalize_name(col)
            if keyword in name:
                return col

    return None


def save_figure(fig, filename):
    path = OUTPUT_DIR / filename
    fig.savefig(path, dpi=250, bbox_inches="tight")
    plt.close(fig)
    print(f"图片生成成功：{path}")


# =====================================================
# 3. 图一：系统总体架构图
# =====================================================

def draw_architecture():

    fig, ax = plt.subplots(figsize=(16, 5))
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")

    ax.set_title(
        "基于 FPGA 的振动监测与异常识别系统架构",
        fontsize=20,
        fontweight="bold",
        pad=20
    )

    nodes = [
        "PC端\n模拟振动CSV",
        "UART发送\nCOM8",
        "FPGA UART\n数据接收",
        "FIR\n低通滤波",
        "FFT\n1024点",
        "UART\n频谱回传",
        "PC端\n特征提取与分类"
    ]

    xs = np.linspace(0.08, 0.92, len(nodes))
    y = 0.57
    width = 0.105
    height = 0.22

    for i, (x, label) in enumerate(zip(xs, nodes)):

        rect = FancyBboxPatch(
            (x - width / 2, y - height / 2),
            width,
            height,
            boxstyle="round,pad=0.012",
            linewidth=1.8,
            edgecolor="steelblue",
            facecolor="aliceblue"
        )

        ax.add_patch(rect)

        ax.text(
            x, y, label,
            ha="center",
            va="center",
            fontsize=10,
            fontweight="bold"
        )

        if i < len(nodes) - 1:

            arrow = FancyArrowPatch(
                (x + width / 2 + 0.003, y),
                (xs[i + 1] - width / 2 - 0.003, y),
                arrowstyle="->",
                mutation_scale=15,
                linewidth=1.8,
                color="steelblue"
            )

            ax.add_patch(arrow)

    ax.text(
        0.5, 0.18,
        "输入：1024点 int16 数据    |    "
        "FPGA：FIR + FFT 硬件处理    |    "
        "输出：频谱 CSV + 故障分类结果",
        ha="center",
        fontsize=12
    )

    save_figure(fig, "video_01_architecture.png")


# =====================================================
# 4. 图二：三种状态的 FPGA 频谱对比
# =====================================================

def draw_spectrum():

    fig, ax = plt.subplots(figsize=(12, 6))

    success = 0

    for label, filepath in SPECTRUM_FILES.items():

        if not filepath.exists():
            print(f"频谱文件不存在：{filepath}")
            continue

        df = pd.read_csv(filepath, encoding="utf-8-sig")

        freq_col = find_column(
            df,
            ["frequency_hz", "freq_hz", "frequency", "freq"],
            keyword="frequency"
        )

        mag_col = find_column(
            df,
            ["fpga_mag", "magnitude", "fft_mag",
             "amplitude", "fpga_magnitude"],
            keyword="mag"
        )

        if freq_col is None or mag_col is None:
            print(f"{filepath.name} 列名不匹配：{list(df.columns)}")
            continue

        x = pd.to_numeric(df[freq_col], errors="coerce")
        y = pd.to_numeric(df[mag_col], errors="coerce")

        valid = x.notna() & y.notna()

        x = x[valid].to_numpy()
        y = y[valid].to_numpy()

        order = np.argsort(x)

        ax.plot(
            x[order],
            y[order],
            linewidth=1.6,
            label=label
        )

        success += 1

    if success == 0:
        plt.close(fig)
        print("没有成功读取频谱数据，请检查 CSV 列名和路径。")
        return

    ax.set_title(
        "FPGA 返回的三种振动状态频谱对比",
        fontsize=17,
        fontweight="bold"
    )

    ax.set_xlabel("Frequency (Hz)", fontsize=13)
    ax.set_ylabel("FPGA Magnitude", fontsize=13)

    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=12)

    ax.set_xlim(left=0)

    save_figure(fig, "video_02_spectrum.png")


# =====================================================
# 5. 图三：H2、H3、RMS 特征分布
# =====================================================

def draw_features():

    if not FEATURE_FILE.exists():
        print(f"找不到特征文件：{FEATURE_FILE}")
        return

    df = pd.read_csv(FEATURE_FILE, encoding="utf-8-sig")

    label_col = find_column(
        df,
        ["label", "class", "fault_type", "category"]
    )

    if label_col is None:
        print("没有识别到类别列，当前列名：", list(df.columns))
        return

    feature_candidates = {
        "H2": ["H2", "H2_ratio", "H2_amp", "H2_amplitude_ratio"],
        "H3": ["H3", "H3_ratio", "H3_amp", "H3_amplitude_ratio"],
        "RMS": ["RMS", "RMS_value", "RMS_feature", "PC_Parseval_RMS"]
    }

    feature_cols = {}

    for name, candidates in feature_candidates.items():

        col = find_column(df, candidates)

        if col is None:
            col = find_column(
                df,
                candidates,
                keyword=name.lower()
            )

        if col is not None:
            feature_cols[name] = col

    if not feature_cols:
        print("未识别到 H2、H3、RMS 特征列。")
        print("当前 CSV 列名：", list(df.columns))
        return

    df[label_col] = df[label_col].astype(str)

    expected = ["normal", "looseness", "unbalance"]

    labels = [
        x for x in expected
        if x in df[label_col].unique()
    ]

    if not labels:
        labels = sorted(df[label_col].unique())

    fig, axes = plt.subplots(
        1, len(feature_cols),
        figsize=(6 * len(feature_cols), 5)
    )

    axes = np.atleast_1d(axes)

    for ax, (feature_name, col) in zip(
        axes, feature_cols.items()
    ):

        groups = []

        for label in labels:

            values = pd.to_numeric(
                df.loc[df[label_col] == label, col],
                errors="coerce"
            ).dropna()

            groups.append(values.to_numpy())

        ax.boxplot(
            groups,
            labels=labels,
            showmeans=True
        )

        ax.set_title(
            f"{feature_name} 特征分布",
            fontsize=14,
            fontweight="bold"
        )

        ax.set_xlabel("Fault Class")
        ax.set_ylabel(feature_name)
        ax.grid(axis="y", alpha=0.3)

    fig.suptitle(
        "三种振动状态的特征分布对比",
        fontsize=17,
        fontweight="bold"
    )

    save_figure(fig, "video_03_features.png")


# =====================================================
# 6. 图四：故障分类混淆矩阵
# =====================================================

def draw_confusion_matrix():

    if not CONFUSION_FILE.exists():
        print(f"找不到混淆矩阵：{CONFUSION_FILE}")
        return

    raw = pd.read_csv(
        CONFUSION_FILE,
        encoding="utf-8-sig"
    )

    raw = raw.loc[
        :,
        ~raw.columns.astype(str).str.startswith("Unnamed")
    ]

    if raw.empty:
        print("混淆矩阵为空。")
        return

    first_col = raw.columns[0]

    # 如果第一列是实际类别名称，将其作为行索引
    if pd.to_numeric(raw[first_col], errors="coerce").isna().any():
        raw = raw.set_index(first_col)

    cm = raw.apply(
        pd.to_numeric,
        errors="coerce"
    )

    cm = cm.dropna(axis=0, how="all")
    cm = cm.dropna(axis=1, how="all")

    if cm.empty:
        print("混淆矩阵中没有有效数字。")
        return

    matrix = cm.to_numpy()

    fig, ax = plt.subplots(figsize=(8, 6))

    im = ax.imshow(matrix, cmap="Blues")

    ax.set_xticks(np.arange(len(cm.columns)))
    ax.set_yticks(np.arange(len(cm.index)))

    ax.set_xticklabels(cm.columns)
    ax.set_yticklabels(cm.index)

    ax.set_xlabel("Predicted Label", fontsize=12)
    ax.set_ylabel("Actual Label", fontsize=12)

    ax.set_title(
        "故障分类测试集混淆矩阵",
        fontsize=17,
        fontweight="bold"
    )

    for i in range(matrix.shape[0]):
        for j in range(matrix.shape[1]):

            ax.text(
                j, i,
                f"{matrix[i, j]:.0f}",
                ha="center",
                va="center",
                fontsize=16
            )

    fig.colorbar(im, ax=ax, label="Sample Count")

    save_figure(fig, "video_04_confusion_matrix.png")


# =====================================================
# 7. 图五：系统性能指标可视化
# =====================================================

def draw_performance():

    # 以下数据取自你最近提供的性能测试截图。
    # 如果重新测试后数值发生变化，只修改这里。

    success = 30
    total = 30

    drain_us = 44.360

    end_to_end_ms = 125.017
    p50_ms = 124.923
    p95_ms = 126.256
    p99_ms = 126.708

    fig, ax = plt.subplots(figsize=(13, 6))

    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")

    ax.set_title(
        "FPGA 振动监测系统性能测试结果",
        fontsize=20,
        fontweight="bold",
        pad=20
    )

    cards = [
        (
            0.18,
            "串口通信成功",
            f"{success}/{total}",
            "30帧全部成功"
        ),
        (
            0.50,
            "FPGA 流水线排空时间",
            f"{drain_us:.3f} μs",
            "最后有效输入至最后 FFT 输出"
        ),
        (
            0.82,
            "PC 端到端平均耗时",
            f"{end_to_end_ms:.3f} ms",
            "包含串口与 PC 收发时间"
        )
    ]

    for x, title, value, note in cards:

        rect = FancyBboxPatch(
            (x - 0.14, 0.37),
            0.28,
            0.36,
            boxstyle="round,pad=0.015",
            linewidth=1.8,
            edgecolor="steelblue",
            facecolor="aliceblue"
        )

        ax.add_patch(rect)

        ax.text(
            x, 0.65, title,
            ha="center",
            fontsize=12,
            fontweight="bold"
        )

        ax.text(
            x, 0.52, value,
            ha="center",
            fontsize=21,
            fontweight="bold"
        )

        ax.text(
            x, 0.42, note,
            ha="center",
            fontsize=8.5
        )

    ax.text(
        0.5, 0.23,
        f"P50：{p50_ms:.3f} ms    "
        f"P95：{p95_ms:.3f} ms    "
        f"P99：{p99_ms:.3f} ms",
        ha="center",
        fontsize=13
    )

    ax.text(
        0.5, 0.10,
        "注意：FPGA 流水线排空时间与 PC 端到端耗时的测量边界不同，"
        "不能直接据此计算加速比。",
        ha="center",
        fontsize=10
    )

    save_figure(fig, "video_05_performance.png")


# =====================================================
# 8. 主程序
# =====================================================

def main():

    print("\n========== 开始生成视频可视化素材 ==========\n")

    draw_architecture()

    draw_spectrum()

    draw_features()

    draw_confusion_matrix()

    draw_performance()

    print("\n========== 可视化素材生成结束 ==========")

    print("\n请检查以下目录：")
    print(OUTPUT_DIR)

    print("\n生成的图片：")
    for file in OUTPUT_DIR.glob("video_*.png"):
        print(" -", file.name)


if __name__ == "__main__":
    main()
