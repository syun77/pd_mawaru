#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
level_editor.py

Playdate向け円環ライン接続パズル pd_mawaru の簡易レベルエディタです。

主な機能:
- 可変サイズの盤面編集
- 4種類のパネル配置
- board.lua の checkEraseList 相当のループ検出
- 消去対象ハイライト
- JSON保存/読込
- Luaステージデータ出力

Python 3.10+ 推奨。標準ライブラリのみ使用します。
"""

from __future__ import annotations

import copy
import json
import os
import random
import sys
from enum import IntEnum
from datetime import datetime
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any, Dict, List, Optional, Set, Tuple
# tkinterの存在チェック.
try:
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
    TK_IMPORT_ERROR = None
except ModuleNotFoundError as exc:
    tk = None
    filedialog = None
    messagebox = None
    ttk = None
    TK_IMPORT_ERROR = exc

if TYPE_CHECKING:
    import tkinter as tk_types
    from tkinter import ttk as ttk_types

    TkEvent = tk_types.Event[Any]
    TkVariable = tk_types.Variable
    TtkFrame = ttk_types.Frame
else:
    TkEvent = Any
    TkVariable = Any
    TtkFrame = Any


# board.lua の BLOCK と合わせる.
class BlockType(IntEnum):
	EMPTY = 0
	SLASH = 1       # /
	BACKSLASH = 2   # \
	VALLEY = 3      # \/ 谷型: 上辺側の2点を接続
	PEAK = 4        # /\ 山型: 下辺側の2点を接続
# 種別に対応するブロック名.
BLOCK_NAMES = {
    BlockType.EMPTY: "EMPTY",
    BlockType.SLASH: "SLASH /",
    BlockType.BACKSLASH: "BACKSLASH \\",
    BlockType.VALLEY: r"VALLEY \/",
    BlockType.PEAK: "PEAK /\\",
}

BLOCK_SHORT = {
    BlockType.EMPTY: ".",
    BlockType.SLASH: "/",
    BlockType.BACKSLASH: "\\",
    BlockType.VALLEY: "V",
    BlockType.PEAK: "A",
}

# クリア条件の表示用名称.
CLEAR_CONDITION_LABELS = {
    "eraseAll": "全消し",
    "erasePanels": "一定数のパネルを消去",
    "makeLoops": "指定数のループを作成",
    "makeWrapLoop": "円環ループを作成",
    "eraseMarked": "マーク付きパネルを消去",
}

# クリア条件の内部名.
CLEAR_CONDITION_INTERNAL_VALUES = {label: value for value, label in CLEAR_CONDITION_LABELS.items()}

# ステージルール.
@dataclass
class StageRules:
    move_limit: Optional[int] = 10 # 交換可能回数.
    time_limit: Optional[int] = None # 制限時間(秒).
    manual_rise_enabled: bool = False # Bボタンでの手動せり上げが可能かどうか.
    auto_rise_enabled: bool = False # 一定時間の自動せり上げを行うか.
    auto_rise_interval: Optional[float] = None # 自動せり上げの間隔(秒). Noneでデフォルト値を使用.

# クリア条件.
# ・eraseAll: 全消し
# ・erasePanels: 一定数のパネルを消去
# ・makeLoops: 指定数のループを作成
# ・makeWrapLoop: 円環ループを作成
# ・eraseMarked: マーク付きパネルを消去
@dataclass
class ClearCondition:
    type: str = "eraseAll" # クリア条件文字列.
    count: Optional[int] = None
    mark: Optional[str] = None

# ステージデータ.
@dataclass
class StageData:
    version: int = 1
    stage_id: str = "stage_001"
    name: str = "First Loop"
    pack: str = "tutorial"
    columns: int = 10 # 列数.
    rows: int = 6 # 行数.
    cells: List[List[int]] = field(default_factory=list)
    rules: StageRules = field(default_factory=StageRules)
    clear_condition: ClearCondition = field(default_factory=ClearCondition)
    rise_queue: List[List[int]] = field(default_factory=list)
    notes: str = ""

    def ensure_cells(self) -> None:
        if not self.cells:
            self.cells = [[BlockType.EMPTY for _ in range(self.columns)] for _ in range(self.rows)]
            return

        # 行数・列数が足りない/多い場合は調整
        new_cells = [[BlockType.EMPTY for _ in range(self.columns)] for _ in range(self.rows)]
        for r in range(min(self.rows, len(self.cells))):
            for c in range(min(self.columns, len(self.cells[r]))):
                v = int(self.cells[r][c])
                new_cells[r][c] = v if BlockType.EMPTY <= v <= BlockType.PEAK else BlockType.EMPTY
        self.cells = new_cells


class BoardLogic:
    """board.lua の接続・消去判定をPythonへ移植したロジック。"""

    def __init__(self, columns: int, rows: int, cells: List[List[int]]):
        self.columns = columns
        self.rows = rows
        self.cells = cells

    def get_index(self, col: int, row: int) -> int:
        """Lua版Array2Dと同じ1始まりindex。col,rowも1始まり。"""
        if col < 1 or col > self.columns or row < 1 or row > self.rows:
            return -1
        return (row - 1) * self.columns + col

    def index_to_cell(self, index: int) -> Tuple[int, int]:
        col = ((index - 1) % self.columns) + 1
        row = ((index - 1) // self.columns) + 1
        return col, row

    def get_cell(self, col: int, row: int) -> int:
        return self.cells[row - 1][col - 1]

    def get_node_id(self, column_boundary: int, row_boundary: int) -> int:
        # board.lua:
        # local normalizedColumn = ((columnBoundary - 1) % columns) + 1
        # return rowBoundary * columns + normalizedColumn
        normalized_column = ((column_boundary - 1) % self.columns) + 1
        return row_boundary * self.columns + normalized_column

    def get_cell_edge(self, col: int, row: int, block_type: int) -> Tuple[Optional[int], Optional[int]]:
        # board.luaの意味に合わせる。
        # outer = row, inner = row + 1
        outer_left = self.get_node_id(col, row)
        outer_right = self.get_node_id(col + 1, row)
        inner_left = self.get_node_id(col, row + 1)
        inner_right = self.get_node_id(col + 1, row + 1)

        if block_type == BlockType.SLASH:
            return inner_left, outer_right
        if block_type == BlockType.BACKSLASH:
            return outer_left, inner_right
        if block_type == BlockType.VALLEY:
            return outer_left, outer_right
        if block_type == BlockType.PEAK:
            return inner_left, inner_right
        return None, None

    @staticmethod
    def add_adjacency(adjacency: Dict[int, List[int]], lookup: Dict[int, Set[int]], a: int, b: int) -> None:
        if a not in lookup:
            lookup[a] = set()
            adjacency[a] = []
        if b not in lookup:
            lookup[b] = set()
            adjacency[b] = []
        if b not in lookup[a]:
            lookup[a].add(b)
            lookup[b].add(a)
            adjacency[a].append(b)
            adjacency[b].append(a)

    def build_cell_graph(self) -> Tuple[Dict[int, List[int]], Dict[int, List[int]], Dict[int, Tuple[int, int]]]:
        node_to_cells: Dict[int, List[int]] = {}
        edge_by_index: Dict[int, Tuple[int, int]] = {}
        adjacency: Dict[int, List[int]] = {}
        adjacency_lookup: Dict[int, Set[int]] = {}

        for row in range(1, self.rows + 1):
            for col in range(1, self.columns + 1):
                block_type = self.get_cell(col, row)
                if block_type == BlockType.EMPTY:
                    continue

                index = self.get_index(col, row)
                a, b = self.get_cell_edge(col, row, block_type)
                if a is None or b is None:
                    continue

                edge_by_index[index] = (a, b)
                node_to_cells.setdefault(a, []).append(index)
                node_to_cells.setdefault(b, []).append(index)

        # 同一ノードを共有するセル同士を隣接扱いにする
        for cells_at_node in node_to_cells.values():
            for i in range(len(cells_at_node)):
                for j in range(i + 1, len(cells_at_node)):
                    self.add_adjacency(adjacency, adjacency_lookup, cells_at_node[i], cells_at_node[j])

        return adjacency, node_to_cells, edge_by_index

    def is_edge_in_cycle(
        self,
        edge_index: int,
        edge_by_index: Dict[int, Tuple[int, int]],
        node_to_cells: Dict[int, List[int]],
    ) -> bool:
        edge = edge_by_index.get(edge_index)
        if edge is None:
            return False

        start_node, goal_node = edge
        queue = [start_node]
        head = 0
        visited_nodes = {start_node}

        while head < len(queue):
            current_node = queue[head]
            head += 1

            for next_edge_index in node_to_cells.get(current_node, []):
                if next_edge_index == edge_index:
                    continue

                next_edge = edge_by_index.get(next_edge_index)
                if next_edge is None:
                    continue

                a, b = next_edge
                if a == current_node:
                    next_node = b
                elif b == current_node:
                    next_node = a
                else:
                    continue

                if next_node == goal_node:
                    return True

                if next_node not in visited_nodes:
                    visited_nodes.add(next_node)
                    queue.append(next_node)

        return False

    def collect_connected_indices(
        self,
        start_index: int,
        adjacency: Dict[int, List[int]],
        allow_set: Set[int],
        visited: Set[int],
    ) -> List[int]:
        ordered: List[int] = []
        stack = [start_index]

        while stack:
            current = stack.pop()
            if current in visited or current not in allow_set:
                continue

            visited.add(current)
            ordered.append(current)

            for neighbor in adjacency.get(current, []):
                if neighbor in allow_set and neighbor not in visited:
                    stack.append(neighbor)

        return ordered

    def check_erase_groups(self) -> List[List[int]]:
        adjacency, node_to_cells, edge_by_index = self.build_cell_graph()
        cycle_cell_set: Set[int] = set()
        max_index = self.columns * self.rows

        for edge_index in range(1, max_index + 1):
            if edge_index in edge_by_index and self.is_edge_in_cycle(edge_index, edge_by_index, node_to_cells):
                cycle_cell_set.add(edge_index)

        visited: Set[int] = set()
        groups: List[List[int]] = []

        for row in range(1, self.rows + 1):
            for col in range(1, self.columns + 1):
                index = self.get_index(col, row)
                block_type = self.get_cell(col, row)
                if block_type != BlockType.EMPTY and index in cycle_cell_set and index not in visited:
                    component = self.collect_connected_indices(index, adjacency, cycle_cell_set, visited)
                    if component:
                        groups.append(component)

        return groups

    def check_erase_coords(self) -> Set[Tuple[int, int]]:
        coords: Set[Tuple[int, int]] = set()
        for group in self.check_erase_groups():
            for index in group:
                coords.add(self.index_to_cell(index))
        return coords

    def one_move_loop_candidates(self) -> List[Tuple[int, int]]:
        """上下入れ替え1手でループができる候補を返す。戻り値は1始まり(col,row)。"""
        result: List[Tuple[int, int]] = []
        if self.check_erase_groups():
            return result

        for row in range(2, self.rows + 1):
            for col in range(1, self.columns + 1):
                copied = [line[:] for line in self.cells]
                copied[row - 1][col - 1], copied[row - 2][col - 1] = copied[row - 2][col - 1], copied[row - 1][col - 1]
                logic = BoardLogic(self.columns, self.rows, copied)
                if logic.check_erase_groups():
                    result.append((col, row))
        return result


class TestPlayWindow(tk.Toplevel if tk is not None else object):
    """簡易テストプレイ用の別ウィンドウ。"""

    def __init__(self, parent: "LevelEditor", stage: StageData, start_col: int, start_row: int):
        super().__init__(parent)
        self.parent_window = parent
        self.title("テストプレイモード")
        self.resizable(False, False)

        self.columns = stage.columns
        self.rows = stage.rows
        self.initial_cells = [row[:] for row in stage.cells]
        self.cells = [row[:] for row in self.initial_cells]

        self.cursor_col = max(1, min(self.columns, int(start_col)))
        self.cursor_row = max(2, min(self.rows, int(start_row)))
        self.initial_cursor_col = self.cursor_col
        self.initial_cursor_row = self.cursor_row
        self.move_count = 0
        self.is_erasing = False
        self.erase_blink_visible = True
        self.erase_targets: Set[Tuple[int, int]] = set()
        self.erase_blink_ticks_left = 0
        self.erase_after_id: Any = None

        self.cell_size = 56
        self.margin = 24

        self.var_status = tk.StringVar()

        self._build_ui()
        self._bind_keys()
        self._update_status()
        self.draw_board()

        self.protocol("WM_DELETE_WINDOW", self.on_close)
        self.transient(parent)
        self.focus_force()
        self.canvas.focus_set()

    def on_close(self) -> None:
        if self.erase_after_id is not None:
            try:
                self.after_cancel(self.erase_after_id)
            except Exception:
                pass
            self.erase_after_id = None
        if hasattr(self, "parent_window"):
            self.parent_window.focus_editor_canvas()
        self.destroy()

    def _build_ui(self) -> None:
        root = ttk.Frame(self)
        root.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        info = ttk.Frame(root)
        info.pack(fill=tk.X)
        ttk.Label(info, text="操作: カーソルキーで移動, Space で入れ替え, Rでリスタート, Esc で閉じる").pack(side=tk.LEFT)
        ttk.Button(info, text="リスタート", command=self.restart).pack(side=tk.RIGHT)

        self.status_label = ttk.Label(root, textvariable=self.var_status)
        self.status_label.pack(anchor=tk.W, pady=(6, 8))

        width = self.margin * 2 + self.columns * self.cell_size
        height = self.margin * 2 + self.rows * self.cell_size
        self.canvas = tk.Canvas(root, width=width, height=height, bg="white", highlightthickness=1, highlightbackground="#d0d0d0")
        self.canvas.pack()
        self.canvas.bind("<Button-1>", lambda e: self.canvas.focus_set())
        self.bind("<FocusIn>", lambda e: self.canvas.focus_set())

    def _bind_keys(self) -> None:
        self.bind_all("<KeyPress>", self.on_global_keypress, add="+")

    def is_active_window(self) -> bool:
        try:
            focused_widget = self.focus_get()
            return focused_widget is not None and focused_widget.winfo_toplevel() is self
        except Exception:
            return False

    def on_global_keypress(self, event: TkEvent) -> str | None:
        if not self.is_active_window():
            return None

        keysym = getattr(event, "keysym", "")
        if keysym == "Up":
            self.move_cursor(0, -1)
            return "break"
        if keysym == "Down":
            self.move_cursor(0, 1)
            return "break"
        if keysym == "Left":
            self.move_cursor(-1, 0)
            return "break"
        if keysym == "Right":
            self.move_cursor(1, 0)
            return "break"
        if keysym == "space":
            self.swap_vertical()
            return "break"
        if keysym in {"r", "R"}:
            self.restart()
            return "break"
        if keysym == "Escape":
            self.destroy()
            return "break"

        return None

    def _update_status(self) -> None:
        self.var_status.set(
            f"列: {self.cursor_col} / カーソル行: {self.cursor_row} と {self.cursor_row - 1} / 手数: {self.move_count}"
        )

    def move_cursor(self, dx: int, dy: int) -> None:
        if self.is_erasing:
            return

        # 列は円環なので左右移動はループさせる。
        self.cursor_col = ((self.cursor_col + dx - 1) % self.columns) + 1
        self.cursor_row = max(2, min(self.rows, self.cursor_row + dy))
        self._update_status()
        self.draw_board()

    def swap_vertical(self) -> None:
        if self.is_erasing:
            return

        row = self.cursor_row
        col = self.cursor_col
        self.cells[row - 1][col - 1], self.cells[row - 2][col - 1] = self.cells[row - 2][col - 1], self.cells[row - 1][col - 1]
        self.move_count += 1
        self._update_status()
        self.start_erase_if_needed()

    def restart(self) -> None:
        if self.erase_after_id is not None:
            try:
                self.after_cancel(self.erase_after_id)
            except Exception:
                pass
            self.erase_after_id = None

        self.is_erasing = False
        self.erase_targets = set()
        self.erase_blink_visible = True
        self.erase_blink_ticks_left = 0
        self.cells = [row[:] for row in self.initial_cells]
        self.cursor_col = self.initial_cursor_col
        self.cursor_row = self.initial_cursor_row
        self.move_count = 0
        self._update_status()
        self.draw_board()

    def get_erase_targets(self) -> Set[Tuple[int, int]]:
        logic = BoardLogic(self.columns, self.rows, self.cells)
        groups = logic.check_erase_groups()
        targets: Set[Tuple[int, int]] = set()
        for group in groups:
            for index in group:
                targets.add(logic.index_to_cell(index))
        return targets

    def start_erase_if_needed(self) -> None:
        targets = self.get_erase_targets()
        if not targets:
            self.draw_board()
            return

        self.is_erasing = True
        self.erase_targets = targets
        self.erase_blink_visible = True
        self.erase_blink_ticks_left = 8
        self.draw_board()
        self.step_erase_blink()

    def step_erase_blink(self) -> None:
        self.erase_blink_ticks_left -= 1
        if self.erase_blink_ticks_left <= 0:
            self.finalize_erase()
            return

        self.erase_blink_visible = not self.erase_blink_visible
        self.draw_board()
        self.erase_after_id = self.after(120, self.step_erase_blink)

    def finalize_erase(self) -> None:
        for col, row in self.erase_targets:
            self.cells[row - 1][col - 1] = BlockType.EMPTY

        self.is_erasing = False
        self.erase_targets = set()
        self.erase_blink_visible = True
        self.erase_blink_ticks_left = 0
        self.erase_after_id = None
        self.draw_board()

        # 消去後に新しいループが残っていれば連鎖的に消去する。
        self.start_erase_if_needed()

    def draw_board(self) -> None:
        self.canvas.delete("all")
        size = self.cell_size
        margin = self.margin

        for row in range(1, self.rows + 1):
            y = margin + (row - 1) * size
            self.canvas.create_text(margin - 10, y + size / 2, text=str(row), anchor=tk.E, fill="#555")

            for col in range(1, self.columns + 1):
                x = margin + (col - 1) * size
                block = self.cells[row - 1][col - 1]

                is_cursor = (col == self.cursor_col and (row == self.cursor_row or row == self.cursor_row - 1))
                is_blink_target = (col, row) in self.erase_targets
                fill = "#fefefe"
                outline = "#b0b0b0"
                line_fill = "#222222"

                if is_cursor:
                    fill = "#e9f3ff"
                    outline = "#0a66c2"

                if is_blink_target:
                    fill = "#ffe8e8" if self.erase_blink_visible else "#ffffff"
                    outline = "#d9534f" if self.erase_blink_visible else "#b0b0b0"

                self.canvas.create_rectangle(x, y, x + size, y + size, fill=fill, outline=outline, width=2 if is_cursor else 1)

                if block == BlockType.EMPTY or (is_blink_target and not self.erase_blink_visible):
                    continue

                pad = 9
                left = x + pad
                right = x + size - pad
                top = y + pad
                bottom = y + size - pad
                mid_x = x + size / 2
                line_width = 4

                if block == BlockType.SLASH:
                    self.canvas.create_line(left, bottom, right, top, width=line_width, fill=line_fill, capstyle=tk.ROUND)
                elif block == BlockType.BACKSLASH:
                    self.canvas.create_line(left, top, right, bottom, width=line_width, fill=line_fill, capstyle=tk.ROUND)
                elif block == BlockType.VALLEY:
                    apex_y = top + (bottom - top) * 0.65
                    self.canvas.create_line(left, top, mid_x, apex_y, width=line_width, fill=line_fill, capstyle=tk.ROUND)
                    self.canvas.create_line(right, top, mid_x, apex_y, width=line_width, fill=line_fill, capstyle=tk.ROUND)
                elif block == BlockType.PEAK:
                    apex_y = top + (bottom - top) * 0.35
                    self.canvas.create_line(left, bottom, mid_x, apex_y, width=line_width, fill=line_fill, capstyle=tk.ROUND)
                    self.canvas.create_line(right, bottom, mid_x, apex_y, width=line_width, fill=line_fill, capstyle=tk.ROUND)

        cursor_x = margin + (self.cursor_col - 1) * size
        top_row_y = margin + (self.cursor_row - 2) * size
        self.canvas.create_rectangle(
            cursor_x + 3,
            top_row_y + 3,
            cursor_x + size - 3,
            top_row_y + size * 2 - 3,
            outline="#0a66c2",
            width=2,
            dash=(6, 4),
        )

        for col in range(1, self.columns + 1):
            x = margin + (col - 1) * size + size / 2
            self.canvas.create_text(x, margin - 10, text=str(col), fill="#555")

# ------------------------------------------------------------------
# レベルエディタ.
# ------------------------------------------------------------------
class LevelEditor(tk.Tk if tk is not None else object):
    def __init__(self):
        super().__init__()
        self.title("pd_mawaru Level Editor")
        self.geometry("1060x720")
        self.minsize(900, 600)

        self.stage = StageData()
        self.stage.ensure_cells()

        self.cell_size = 56
        self.margin = 24
        self.selected_col = 1
        self.selected_row = 1
        self.current_block = BlockType.SLASH
        self.show_erase_preview = tk.BooleanVar(value=True)
        self.show_wrap_columns = tk.BooleanVar(value=True)
        self.erase_coords: Set[Tuple[int, int]] = set()
        self.one_move_candidates: List[Tuple[int, int]] = []
        self.drag_source_cell: Optional[Tuple[int, int]] = None
        self.drag_target_cell: Optional[Tuple[int, int]] = None
        self.drag_started = False
        self.drag_moved = False
        self.last_saved_path = None  # 最後に保存したファイルパスを保持する変数
        self.config_path = os.path.join(os.path.dirname(__file__), ".level_editor_config.json")
        self.app_config: Dict[str, Any] = self.default_app_config()
        self.undo_stack: List[Dict[str, Any]] = []
        self.redo_stack: List[Dict[str, Any]] = []
        self.max_undo_steps = 100

        self._build_ui()
        self._bind_keys()
        self.protocol("WM_DELETE_WINDOW", self.on_close)
        self.load_app_config()
        self.refresh_analysis()
        self.draw_board()

    @staticmethod
    def default_app_config() -> Dict[str, Any]:
        return {
            "version": 1,
            "settings": {},
            "history": {
                "opened": [],
                "saved": [],
            },
            "last_opened_file": None,
        }

    def on_close(self) -> None:
        self.save_app_config()
        self.destroy()

    def _parse_optional_int(self, value: str) -> Optional[int]:
        text = str(value).strip()
        if text == "":
            return None
        try:
            return int(text)
        except Exception:
            return None

    def collect_settings_for_config(self) -> Dict[str, Any]:
        return {
            "stage_id": self.var_stage_id.get().strip() or self.stage.stage_id,
            "name": self.var_name.get().strip() or self.stage.name,
            "pack": self.var_pack.get().strip() or self.stage.pack,
            "columns": int(self.var_columns.get()),
            "rows": int(self.var_rows.get()),
            "move_limit": self._parse_optional_int(self.var_move_limit.get()),
            "clear_type": self.clear_condition_internal_value(self.var_clear_type.get().strip() or "全消し"),
            "clear_count": self._parse_optional_int(self.var_clear_count.get()),
            "manual_rise_enabled": bool(self.var_manual_rise.get()),
            "auto_rise_enabled": bool(self.var_auto_rise.get()),
            "show_erase_preview": bool(self.show_erase_preview.get()),
            "show_wrap_columns": bool(self.show_wrap_columns.get()),
            "selected_col": int(self.selected_col),
            "selected_row": int(self.selected_row),
            "current_block": int(self.current_block),
            "last_saved_path": self.last_saved_path,
            "window_geometry": self.geometry(),
        }

    def apply_settings_from_config(self, settings: Dict[str, Any]) -> None:
        if not settings:
            return

        self.stage.stage_id = str(settings.get("stage_id", self.stage.stage_id))
        self.stage.name = str(settings.get("name", self.stage.name))
        self.stage.pack = str(settings.get("pack", self.stage.pack))
        self.stage.columns = max(4, min(24, int(settings.get("columns", self.stage.columns))))
        self.stage.rows = max(3, min(12, int(settings.get("rows", self.stage.rows))))
        self.stage.rules.move_limit = settings.get("move_limit", self.stage.rules.move_limit)
        self.stage.clear_condition.type = str(settings.get("clear_type", self.stage.clear_condition.type))
        self.stage.clear_condition.count = settings.get("clear_count", self.stage.clear_condition.count)
        self.stage.rules.manual_rise_enabled = bool(settings.get("manual_rise_enabled", self.stage.rules.manual_rise_enabled))
        self.stage.rules.auto_rise_enabled = bool(settings.get("auto_rise_enabled", self.stage.rules.auto_rise_enabled))
        self.stage.ensure_cells()

        self.sync_ui_from_stage()
        self.show_erase_preview.set(bool(settings.get("show_erase_preview", self.show_erase_preview.get())))
        self.show_wrap_columns.set(bool(settings.get("show_wrap_columns", self.show_wrap_columns.get())))

        self.current_block = int(settings.get("current_block", self.current_block))
        if self.current_block < BlockType.EMPTY or self.current_block > BlockType.PEAK:
            self.current_block = BlockType.SLASH
        self.var_brush.set(self.current_block)

        selected_col = int(settings.get("selected_col", self.selected_col))
        selected_row = int(settings.get("selected_row", self.selected_row))
        self.selected_col = max(1, min(self.stage.columns, selected_col))
        self.selected_row = max(1, min(self.stage.rows, selected_row))

        last_saved = settings.get("last_saved_path")
        self.last_saved_path = str(last_saved) if last_saved else None

        geometry = settings.get("window_geometry")
        if geometry:
            try:
                self.geometry(str(geometry))
            except Exception:
                pass

    def append_history(self, kind: str, path: str) -> None:
        history = self.app_config.setdefault("history", {})
        records = history.setdefault(kind, [])
        normalized = os.path.abspath(path)
        now = datetime.now().isoformat(timespec="seconds")

        records = [r for r in records if isinstance(r, dict) and r.get("path") != normalized]
        records.insert(0, {"path": normalized, "at": now})
        history[kind] = records[:20]
        self.app_config["history"] = history

    def get_recent_files(self) -> List[str]:
        history = self.app_config.get("history", {})
        opened = history.get("opened", []) if isinstance(history, dict) else []
        saved = history.get("saved", []) if isinstance(history, dict) else []

        result: List[str] = []
        seen: Set[str] = set()

        for source in [opened, saved]:
            if not isinstance(source, list):
                continue
            for rec in source:
                if not isinstance(rec, dict):
                    continue
                path = rec.get("path")
                if not isinstance(path, str) or not path:
                    continue
                normalized = os.path.abspath(path)
                if normalized in seen:
                    continue
                seen.add(normalized)
                result.append(normalized)

        return result[:20]

    def refresh_recent_files_menu(self) -> None:
        if not hasattr(self, "recent_open_menu"):
            return

        self.recent_open_menu.delete(0, tk.END)
        recent_files = self.get_recent_files()
        if not recent_files:
            self.recent_open_menu.add_command(label="履歴なし", state=tk.DISABLED)
            return

        for path in recent_files:
            exists = os.path.isfile(path)
            base_name = os.path.basename(path) or path
            label = f"{base_name}"
            if not exists:
                label += " (見つかりません)"

            if exists:
                self.recent_open_menu.add_command(
                    label=label,
                    command=lambda p=path: self.load_json_from_path(p),
                )
            else:
                self.recent_open_menu.add_command(label=label, state=tk.DISABLED)

    def load_app_config(self) -> None:
        if not os.path.isfile(self.config_path):
            self.refresh_recent_files_menu()
            return

        try:
            with open(self.config_path, "r", encoding="utf-8") as f:
                loaded = json.load(f)
        except Exception:
            return

        if not isinstance(loaded, dict):
            self.refresh_recent_files_menu()
            return

        self.app_config = self.default_app_config()
        self.app_config.update(loaded)

        settings = self.app_config.get("settings", {})
        if isinstance(settings, dict):
            self.apply_settings_from_config(settings)

        last_opened = self.app_config.get("last_opened_file")
        if isinstance(last_opened, str) and last_opened and os.path.isfile(last_opened):
            self.load_json_from_path(last_opened, show_error=False, record_history=False)
        self.refresh_recent_files_menu()

    def save_app_config(self) -> None:
        self.app_config["settings"] = self.collect_settings_for_config()
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self.app_config, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    def save_json_to_path(self, path: str) -> None:
        try:
            data = self.to_json_dict()
        except Exception as exc:
            messagebox.showerror("エラー", f"ステージ設定の変換に失敗しました。\n{exc}")
            return

        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        normalized = os.path.abspath(path)
        # 最後に編集したファイルパスに設定.
        self.last_saved_path = normalized
        # ファイル名のみを取り出す.
        base_name = os.path.basename(normalized)
        # タイトルバーにファイル名を表示.
        self.title(f"Level Editor - {base_name}")
        self.app_config["last_opened_file"] = normalized
        self.append_history("saved", normalized)
        self.save_app_config()
        self.refresh_recent_files_menu()

    def load_json_from_path(self, path: str, show_error: bool = True, record_history: bool = True) -> bool:
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.load_from_json_dict(data)
        except Exception as exc:
            if show_error:
                messagebox.showerror("エラー", f"JSON読込に失敗しました。\n{exc}")
            return False

        normalized = os.path.abspath(path)
        # 最後に編集したファイルパスに設定.
        self.last_saved_path = normalized
        # ファイル名のみを取り出す.
        base_name = os.path.basename(normalized)
        # タイトルバーにファイル名を表示.
        self.title(f"Level Editor - {base_name}")
        self.app_config["last_opened_file"] = normalized
        if record_history:
            self.append_history("opened", normalized)
        self.save_app_config()
        self.refresh_recent_files_menu()
        return True

    # ------------------------------------------------------------------ UI

    def _build_menu_bar(self) -> None:
        menu_bar = tk.Menu(self)

        self.file_menu = tk.Menu(menu_bar, tearoff=False)
        self.file_menu.add_command(label="JSON保存", command=self.save_json)
        self.file_menu.add_command(label="JSON上書き保存", command=self.save_json_overwrite)
        self.file_menu.add_command(label="JSON読込", command=self.load_json)

        self.recent_open_menu = tk.Menu(self.file_menu, tearoff=False)
        self.file_menu.add_cascade(label="履歴から開く", menu=self.recent_open_menu)

        self.file_menu.add_separator()
        self.file_menu.add_command(label="Luaステージ出力", command=self.export_lua)
        self.file_menu.add_command(label="Luaをクリップボードへコピー", command=self.copy_lua_to_clipboard)
        menu_bar.add_cascade(label="ファイル", menu=self.file_menu)

        edit_menu = tk.Menu(menu_bar, tearoff=False)
        edit_menu.add_command(label="全消去", command=self.clear_board)
        edit_menu.add_command(label="ランダム", command=self.randomize_board)
        edit_menu.add_separator()
        edit_menu.add_command(label="左へ回転", command=lambda: self.rotate_columns(-1))
        edit_menu.add_command(label="右へ回転", command=lambda: self.rotate_columns(1))
        edit_menu.add_separator()
        edit_menu.add_command(label="選択列を上へ", command=lambda: self.shift_column(-1))
        edit_menu.add_command(label="選択列を下へ", command=lambda: self.shift_column(1))
        menu_bar.add_cascade(label="編集", menu=edit_menu)

        test_menu = tk.Menu(menu_bar, tearoff=False)
        test_menu.add_command(label="テストプレイ開始", command=self.open_test_play_mode)
        menu_bar.add_cascade(label="テスト", menu=test_menu)

        self.refresh_recent_files_menu()

        self.config(menu=menu_bar)

    def _build_ui(self) -> None:
        self._build_menu_bar()

        root = ttk.Frame(self)
        root.pack(fill=tk.BOTH, expand=True)

        left = ttk.Frame(root)
        left.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        toolbar = ttk.Frame(left)
        toolbar.pack(fill=tk.X, padx=8, pady=(8, 2))
        self.undo_button = ttk.Button(toolbar, text="Undo", command=self.on_undo_button_click, takefocus=False)
        self.undo_button.pack(side=tk.LEFT, padx=2)
        self.redo_button = ttk.Button(toolbar, text="Redo", command=self.on_redo_button_click, takefocus=False)
        self.redo_button.pack(side=tk.LEFT, padx=2)

        self.canvas = tk.Canvas(left, bg="white", highlightthickness=0)
        self.canvas.pack(fill=tk.BOTH, expand=True)
        self.canvas.bind("<Motion>", self.on_mouse_move)
        self.canvas.bind("<ButtonPress-1>", self.on_left_button_press)
        self.canvas.bind("<B1-Motion>", self.on_left_drag)
        self.canvas.bind("<ButtonRelease-1>", self.on_left_button_release)
        self.canvas.bind("<Button-3>", self.on_right_click)
        self.canvas.bind("<MouseWheel>", self.on_mouse_wheel)
        self.canvas.focus_set()

        bottom = ttk.Frame(left)
        bottom.pack(fill=tk.X, padx=8, pady=6)
        ttk.Button(bottom, text="消去プレビュー更新", command=self.refresh_and_draw).pack(side=tk.LEFT, padx=2)
        ttk.Button(bottom, text="1手候補", command=self.show_one_move_candidates).pack(side=tk.LEFT, padx=2)
        ttk.Button(bottom, text="テストプレイ", command=self.open_test_play_mode).pack(side=tk.LEFT, padx=2)
        ttk.Checkbutton(bottom, text="消去対象を表示", variable=self.show_erase_preview, command=self.draw_board).pack(side=tk.LEFT, padx=8)
        ttk.Checkbutton(bottom, text="左右複製列を表示", variable=self.show_wrap_columns, command=self.draw_board).pack(side=tk.LEFT, padx=8)

        right = ttk.Frame(root, width=300)
        right.pack(side=tk.RIGHT, fill=tk.Y, padx=8, pady=8)
        right.pack_propagate(False)

        self._build_stage_panel(right)
        self._build_brush_panel(right)
        self._build_info_panel(right)
        self.update_undo_redo_buttons()

    def _build_stage_panel(self, parent: TtkFrame) -> None:
        group = ttk.LabelFrame(parent, text="ステージ設定")
        group.pack(fill=tk.X, pady=4)

        self.var_stage_id = tk.StringVar(value=self.stage.stage_id)
        self.var_name = tk.StringVar(value=self.stage.name)
        self.var_pack = tk.StringVar(value=self.stage.pack)
        self.var_columns = tk.IntVar(value=self.stage.columns)
        self.var_rows = tk.IntVar(value=self.stage.rows)
        self.var_move_limit = tk.StringVar(value=str(self.stage.rules.move_limit or ""))
        self.var_clear_type = tk.StringVar(value=self.clear_condition_display_value(self.stage.clear_condition.type))
        self.var_clear_count = tk.StringVar(value="" if self.stage.clear_condition.count is None else str(self.stage.clear_condition.count))
        self.var_manual_rise = tk.BooleanVar(value=self.stage.rules.manual_rise_enabled)
        self.var_auto_rise = tk.BooleanVar(value=self.stage.rules.auto_rise_enabled)

        self._labeled_entry(group, "id", self.var_stage_id)
        self._labeled_entry(group, "name", self.var_name)
        self._labeled_entry(group, "pack", self.var_pack)

        size_row = ttk.Frame(group)
        size_row.pack(fill=tk.X, padx=6, pady=2)
        ttk.Label(size_row, text="列 x 行", width=10).pack(side=tk.LEFT)
        ttk.Spinbox(size_row, from_=4, to=24, textvariable=self.var_columns, width=2).pack(side=tk.LEFT)
        ttk.Label(size_row, text="x", width=2).pack(side=tk.LEFT, padx=(2, 2))
        ttk.Spinbox(size_row, from_=3, to=12, textvariable=self.var_rows, width=2).pack(side=tk.LEFT)
        ttk.Button(size_row, text="適用", command=self.apply_resize).pack(side=tk.RIGHT)

        self._labeled_entry(group, "手数制限", self.var_move_limit)

        row = ttk.Frame(group)
        row.pack(fill=tk.X, padx=6, pady=2)
        ttk.Label(row, text="クリア条件", width=10).pack(side=tk.LEFT)
        clear_combo = ttk.Combobox(
            row,
            textvariable=self.var_clear_type,
            state="readonly",
            values=list(CLEAR_CONDITION_INTERNAL_VALUES.keys()),
            width=15,
        )
        clear_combo.pack(side=tk.LEFT, fill=tk.X, expand=True)

        self._labeled_entry(group, "clearCount", self.var_clear_count)
        ttk.Checkbutton(group, text="手動せり上げ (Bボタン) が可能かどうか？", variable=self.var_manual_rise).pack(anchor=tk.W, padx=6)
        ttk.Checkbutton(group, text="一定時間の自動せり上がりを行うか", variable=self.var_auto_rise).pack(anchor=tk.W, padx=6)

    def _build_brush_panel(self, parent: TtkFrame) -> None:
        group = ttk.LabelFrame(parent, text="ブラシ")
        group.pack(fill=tk.X, pady=4)
        self.var_brush = tk.IntVar(value=self.current_block)
        for value in [BlockType.EMPTY, BlockType.SLASH, BlockType.BACKSLASH, BlockType.VALLEY, BlockType.PEAK]:
            self._build_brush_option(group, value)

        ttk.Label(group, text="キー: 0-4 / Spaceでセル切替 / 右クリックで空白").pack(anchor=tk.W, padx=6, pady=(4, 2))

    def _build_brush_option(self, parent: TtkFrame, value: int) -> None:
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, padx=6, pady=2)

        radio = ttk.Radiobutton(
            row,
            value=value,
            variable=self.var_brush,
            command=self.on_brush_changed,
        )
        radio.pack(side=tk.LEFT)

        preview = tk.Canvas(row, width=36, height=36, bg="white", highlightthickness=1, highlightbackground="#c8c8c8")
        preview.pack(side=tk.LEFT, padx=(2, 8))
        self.draw_brush_preview(preview, value)

        label = ttk.Label(row, text=f"{value}: {BLOCK_NAMES[value]}")
        label.pack(side=tk.LEFT)

        def select_brush(_: TkEvent | None = None, *, selected_value: int = value) -> None:
            self.var_brush.set(selected_value)
            self.on_brush_changed()

        preview.bind("<Button-1>", select_brush)
        label.bind("<Button-1>", select_brush)

    def draw_brush_preview(self, canvas: Any, block: int) -> None:
        canvas.delete("all")

        left = 7
        right = 29
        top = 7
        bottom = 29
        mid_x = (left + right) / 2
        line_width = 3
        line_fill = "#222222"

        if block == BlockType.EMPTY:
            canvas.create_rectangle(left, top, right, bottom, outline="#d8d8d8")
            return

        if block == BlockType.SLASH:
            canvas.create_line(left, bottom, right, top, width=line_width, fill=line_fill, capstyle=tk.ROUND)
        elif block == BlockType.BACKSLASH:
            canvas.create_line(left, top, right, bottom, width=line_width, fill=line_fill, capstyle=tk.ROUND)
        elif block == BlockType.VALLEY:
            apex_y = top + (bottom - top) * 0.65
            canvas.create_line(left, top, mid_x, apex_y, width=line_width, fill=line_fill, capstyle=tk.ROUND)
            canvas.create_line(right, top, mid_x, apex_y, width=line_width, fill=line_fill, capstyle=tk.ROUND)
        elif block == BlockType.PEAK:
            apex_y = top + (bottom - top) * 0.35
            canvas.create_line(left, bottom, mid_x, apex_y, width=line_width, fill=line_fill, capstyle=tk.ROUND)
            canvas.create_line(right, bottom, mid_x, apex_y, width=line_width, fill=line_fill, capstyle=tk.ROUND)

    def _build_info_panel(self, parent: TtkFrame) -> None:
        group = ttk.LabelFrame(parent, text="解析情報")
        group.pack(fill=tk.BOTH, expand=True, pady=4)

        self.info_text = tk.Text(group, height=12, wrap=tk.WORD)
        self.info_text.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)
        self.info_text.configure(state=tk.DISABLED)

    @staticmethod
    def _labeled_entry(parent: TtkFrame, label: str, variable: TkVariable) -> None:
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, padx=6, pady=2)
        ttk.Label(row, text=label, width=10).pack(side=tk.LEFT)
        ttk.Entry(row, textvariable=variable).pack(side=tk.LEFT, fill=tk.X, expand=True)

    @staticmethod
    def clear_condition_display_value(internal_value: str) -> str:
        return CLEAR_CONDITION_LABELS.get(internal_value, internal_value)

    @staticmethod
    def clear_condition_internal_value(display_value: str) -> str:
        return CLEAR_CONDITION_INTERNAL_VALUES.get(display_value, display_value)

    def _bind_keys(self) -> None:
        self.bind_all("<KeyPress>", self.on_global_keypress, add="+")

    def is_active_window(self) -> bool:
        try:
            focused_widget = self.focus_get()
            return focused_widget is not None and focused_widget.winfo_toplevel() is self
        except Exception:
            return False

    def is_editable_widget(self, widget: Any) -> bool:
        if widget is None:
            return False

        try:
            widget_class = widget.winfo_class()
        except Exception:
            return False

        return widget_class in {"Entry", "TEntry", "Spinbox", "TSpinbox", "Text", "TCombobox"}

    def on_global_keypress(self, event: TkEvent) -> str | None:
        if not self.is_active_window():
            return None

        widget = getattr(event, "widget", None)
        if self.is_editable_widget(widget):
            keysym = getattr(event, "keysym", "")
            if keysym not in {"Escape", "F5", "Command-z", "Command-y"}:
                return None

        keysym = getattr(event, "keysym", "")
        if keysym == "Left":
            self.move_selection(-1, 0)
            return "break"
        if keysym == "Right":
            self.move_selection(1, 0)
            return "break"
        if keysym == "Up":
            self.move_selection(0, -1)
            return "break"
        if keysym == "Down":
            self.move_selection(0, 1)
            return "break"
        if keysym == "space":
            self.cycle_selected_cell()
            self.focus_editor_canvas()
            return "break"
        if keysym == "Delete":
            self.set_selected_cell(BlockType.EMPTY)
            return "break"
        if keysym == "0":
            self.set_brush_and_cell(BlockType.EMPTY)
            return "break"
        if keysym == "1":
            self.set_brush_and_cell(BlockType.SLASH)
            return "break"
        if keysym == "2":
            self.set_brush_and_cell(BlockType.BACKSLASH)
            return "break"
        if keysym == "3":
            self.set_brush_and_cell(BlockType.VALLEY)
            return "break"
        if keysym == "4":
            self.set_brush_and_cell(BlockType.PEAK)
            return "break"
        if keysym in {"s", "S"} and getattr(event, "state", 0) & 0x0004:
            self.save_json_overwrite()
            return "break"
        if keysym in {"o", "O"} and getattr(event, "state", 0) & 0x0004:
            self.load_json()
            return "break"
        if keysym in {"e", "E"} and getattr(event, "state", 0) & 0x0004:
            self.export_lua()
            return "break"
        if keysym == "F5":
            self.open_test_play_mode()
            return "break"
        if keysym in {"z", "Z"} and getattr(event, "state", 0) & 0x0004:
            self.undo()
            self.focus_editor_canvas()
            return "break"
        if keysym in {"y", "Y"} and getattr(event, "state", 0) & 0x0004:
            self.redo()
            self.focus_editor_canvas()
            return "break"
        if keysym == "Z" and getattr(event, "state", 0) & 0x0004 and getattr(event, "state", 0) & 0x0001:
            self.redo()
            self.focus_editor_canvas()
            return "break"

        return None

    def capture_editor_snapshot(self) -> Dict[str, Any]:
        self.sync_stage_from_ui()
        return {
            "stage": copy.deepcopy(self.to_json_dict()),
            "selected_col": self.selected_col,
            "selected_row": self.selected_row,
            "current_block": int(self.current_block),
            "show_erase_preview": bool(self.show_erase_preview.get()),
            "show_wrap_columns": bool(self.show_wrap_columns.get()),
        }

    def restore_editor_snapshot(self, snapshot: Dict[str, Any]) -> None:
        stage_data = snapshot.get("stage")
        if isinstance(stage_data, dict):
            self.load_from_json_dict(stage_data, clear_history=False)

        self.selected_col = max(1, min(self.stage.columns, int(snapshot.get("selected_col", self.selected_col))))
        self.selected_row = max(1, min(self.stage.rows, int(snapshot.get("selected_row", self.selected_row))))
        self.current_block = int(snapshot.get("current_block", self.current_block))
        if self.current_block < BlockType.EMPTY or self.current_block > BlockType.PEAK:
            self.current_block = BlockType.SLASH
        self.var_brush.set(self.current_block)
        self.show_erase_preview.set(bool(snapshot.get("show_erase_preview", self.show_erase_preview.get())))
        self.show_wrap_columns.set(bool(snapshot.get("show_wrap_columns", self.show_wrap_columns.get())))
        self.refresh_and_draw()

    def push_undo_state(self) -> None:
        self.undo_stack.append(self.capture_editor_snapshot())
        if len(self.undo_stack) > self.max_undo_steps:
            self.undo_stack = self.undo_stack[-self.max_undo_steps :]
        self.redo_stack.clear()
        self.update_undo_redo_buttons()

    def clear_undo_redo_history(self) -> None:
        self.undo_stack.clear()
        self.redo_stack.clear()
        self.update_undo_redo_buttons()

    def update_undo_redo_buttons(self) -> None:
        if hasattr(self, "undo_button"):
            self.undo_button.configure(state=(tk.NORMAL if self.undo_stack else tk.DISABLED))
        if hasattr(self, "redo_button"):
            self.redo_button.configure(state=(tk.NORMAL if self.redo_stack else tk.DISABLED))

    def focus_editor_canvas(self) -> None:
        if hasattr(self, "canvas"):
            self.canvas.focus_set()

    def on_undo_button_click(self) -> None:
        self.undo()
        self.focus_editor_canvas()

    def on_redo_button_click(self) -> None:
        self.redo()
        self.focus_editor_canvas()

    def undo(self) -> None:
        if not self.undo_stack:
            return
        self.redo_stack.append(self.capture_editor_snapshot())
        snapshot = self.undo_stack.pop()
        self.restore_editor_snapshot(snapshot)
        self.update_undo_redo_buttons()

    def redo(self) -> None:
        if not self.redo_stack:
            return
        self.undo_stack.append(self.capture_editor_snapshot())
        snapshot = self.redo_stack.pop()
        self.restore_editor_snapshot(snapshot)
        self.update_undo_redo_buttons()

    # ------------------------------------------------------------------ Drawing

    def draw_board(self) -> None:
        self.canvas.delete("all")
        cols = self.stage.columns
        rows = self.stage.rows
        size = self.cell_size
        margin = self.margin
        show_wrap = self.show_wrap_columns.get()
        wrap_offset = 1 if show_wrap else 0
        total_cols = cols + (2 if show_wrap else 0)

        canvas_width = margin * 2 + total_cols * size
        canvas_height = margin * 2 + rows * size + 40
        self.canvas.configure(scrollregion=(0, 0, canvas_width, canvas_height))

        self.canvas.create_text(
            margin,
            12,
            anchor=tk.W,
            text="矩形表示です。左右端は円環接続として判定されます。薄い複製列は編集対象外です。",
            fill="#555",
        )

        for display_col in range(total_cols):
            actual_col = display_col - wrap_offset + 1
            is_wrap_copy = False
            if show_wrap:
                if display_col == 0:
                    actual_col = cols
                    is_wrap_copy = True
                elif display_col == total_cols - 1:
                    actual_col = 1
                    is_wrap_copy = True
            actual_col = ((actual_col - 1) % cols) + 1

            for row in range(1, rows + 1):
                x = margin + display_col * size
                y = margin + row * size
                self.draw_cell(x, y, actual_col, row, is_wrap_copy)

        # 列番号・行番号
        for display_col in range(total_cols):
            actual_col = display_col - wrap_offset + 1
            if show_wrap and display_col == 0:
                label = f"{cols}*"
            elif show_wrap and display_col == total_cols - 1:
                label = "1*"
            else:
                actual_col = ((actual_col - 1) % cols) + 1
                label = str(actual_col)
            x = margin + display_col * size + size / 2
            self.canvas.create_text(x, margin + 20, text=label, fill="#555")

        for row in range(1, rows + 1):
            self.canvas.create_text(margin - 10, margin + row * size + size / 2, text=str(row), anchor=tk.E, fill="#555")

    def draw_cell(self, x: int, y: int, col: int, row: int, is_wrap_copy: bool) -> None:
        size = self.cell_size
        block = self.stage.cells[row - 1][col - 1]
        is_selected = (col == self.selected_col and row == self.selected_row and not is_wrap_copy)
        is_erase = (col, row) in self.erase_coords and self.show_erase_preview.get()
        is_one_move = (col, row) in self.one_move_candidates

        fill = "#ffffff"
        outline = "#b0b0b0"
        if is_wrap_copy:
            fill = "#f6f6f6"
            outline = "#d6d6d6"
        if is_erase:
            fill = "#ffe6e6"
        if is_one_move and not is_erase:
            fill = "#eef5ff"
        if is_selected:
            outline = "#000000"

        self.canvas.create_rectangle(x, y, x + size, y + size, fill=fill, outline=outline, width=3 if is_selected else 1)

        if is_wrap_copy:
            self.canvas.create_rectangle(x + 4, y + 4, x + size - 4, y + size - 4, outline="#eeeeee")

        if block == BlockType.EMPTY:
            return

        pad = 9
        left = x + pad
        right = x + size - pad
        top = y + pad
        bottom = y + size - pad
        mid_x = x + size / 2
        mid_y = y + size / 2
        line_width = 4
        line_fill = "#222222" if not is_wrap_copy else "#999999"

        if block == BlockType.SLASH:
            self.canvas.create_line(left, bottom, right, top, width=line_width, fill=line_fill, capstyle=tk.ROUND)
        elif block == BlockType.BACKSLASH:
            self.canvas.create_line(left, top, right, bottom, width=line_width, fill=line_fill, capstyle=tk.ROUND)
        elif block == BlockType.VALLEY:
            apex_y = top + (bottom - top) * 0.65
            self.canvas.create_line(left, top, mid_x, apex_y, width=line_width, fill=line_fill, capstyle=tk.ROUND)
            self.canvas.create_line(right, top, mid_x, apex_y, width=line_width, fill=line_fill, capstyle=tk.ROUND)
        elif block == BlockType.PEAK:
            apex_y = top + (bottom - top) * 0.35
            self.canvas.create_line(left, bottom, mid_x, apex_y, width=line_width, fill=line_fill, capstyle=tk.ROUND)
            self.canvas.create_line(right, bottom, mid_x, apex_y, width=line_width, fill=line_fill, capstyle=tk.ROUND)

        self.canvas.create_text(x + size - 7, y + size - 7, text=BLOCK_SHORT[block], fill="#777", font=("TkDefaultFont", 8))

    # ------------------------------------------------------------------ Events

    def canvas_to_cell(self, event_x: int, event_y: int) -> Optional[Tuple[int, int]]:
        size = self.cell_size
        margin = self.margin
        show_wrap = self.show_wrap_columns.get()
        wrap_offset = 1 if show_wrap else 0
        display_col = int((event_x - margin) // size)
        row = int((event_y - margin) // size)

        if row < 1 or row > self.stage.rows:
            return None

        total_cols = self.stage.columns + (2 if show_wrap else 0)
        if display_col < 0 or display_col >= total_cols:
            return None

        if show_wrap and (display_col == 0 or display_col == total_cols - 1):
            return None

        col = display_col - wrap_offset + 1
        if col < 1 or col > self.stage.columns:
            return None
        return col, row

    def update_selected_cell(self, cell: Tuple[int, int]) -> bool:
        col, row = cell
        if self.selected_col == col and self.selected_row == row:
            return False
        self.selected_col, self.selected_row = cell
        self.draw_board()
        return True

    def on_mouse_move(self, event: TkEvent) -> None:
        cell = self.canvas_to_cell(event.x, event.y)
        if cell is None:
            return
        self.update_selected_cell(cell)

    def on_left_button_press(self, event: TkEvent) -> None:
        self.focus_editor_canvas()
        cell = self.canvas_to_cell(event.x, event.y)
        if cell is None:
            self.clear_drag_state()
            return

        self.selected_col, self.selected_row = cell
        self.drag_source_cell = cell
        self.drag_target_cell = cell
        self.drag_started = False
        self.drag_moved = False
        self.draw_board()

    def on_left_drag(self, event: TkEvent) -> None:
        cell = self.canvas_to_cell(event.x, event.y)
        if cell is None:
            return

        self.drag_target_cell = cell
        if self.drag_source_cell is not None and cell != self.drag_source_cell:
            self.drag_moved = True
            source_col, source_row = self.drag_source_cell
            if self.stage.cells[source_row - 1][source_col - 1] != BlockType.EMPTY:
                self.drag_started = True
        self.update_selected_cell(cell)

	# マウスReleaseイベント.
    def on_left_button_release(self, event: TkEvent) -> None:
        self.focus_editor_canvas()
        cell = self.canvas_to_cell(event.x, event.y)
        if cell is None:
            # ドラッグ中にキャンバス外で離した場合は、選択セルを元に戻す
            cell = self.drag_target_cell

        source = self.drag_source_cell
        target = cell
        # ドラッグ操作かどうか.
        was_dragging = self.drag_started and source is not None and target is not None and source != target

        if target is not None:
            # マウスボタンを離した位置がキャンバス内であれば
			# 新しい選択位置に設定.
            self.selected_col, self.selected_row = target

        if was_dragging:
            # ドラッグ操作の場合はセルの内容を入れ替える.
            self.move_cell_contents(source, target)
        elif target is not None:
            self.set_selected_cell(self.current_block)

        self.clear_drag_state()

    def clear_drag_state(self) -> None:
        self.drag_source_cell = None
        self.drag_target_cell = None
        self.drag_started = False
        self.drag_moved = False

    def move_cell_contents(self, source: Tuple[int, int], target: Tuple[int, int]) -> None:
        source_col, source_row = source
        target_col, target_row = target
        if source == target:
            return

        source_value = self.stage.cells[source_row - 1][source_col - 1]
        target_value = self.stage.cells[target_row - 1][target_col - 1]
        if source_value == BlockType.EMPTY:
            return

        self.push_undo_state()

        self.stage.cells[target_row - 1][target_col - 1] = source_value
        self.stage.cells[source_row - 1][source_col - 1] = target_value if target_value != BlockType.EMPTY else BlockType.EMPTY
        self.one_move_candidates = []
        self.refresh_and_draw()

    def on_right_click(self, event: TkEvent) -> None:
        self.focus_editor_canvas()
        cell = self.canvas_to_cell(event.x, event.y)
        if cell is None:
            return
        self.selected_col, self.selected_row = cell
        self.set_selected_cell(BlockType.EMPTY)

    def on_mouse_wheel(self, event: TkEvent) -> None:
        self.focus_editor_canvas()
        cell = self.canvas_to_cell(event.x, event.y)
        if cell is None:
            return
        self.selected_col, self.selected_row = cell
        delta = 1 if event.delta > 0 else -1
        current = self.stage.cells[self.selected_row - 1][self.selected_col - 1]
        self.set_selected_cell((current + delta) % 5)

    def on_brush_changed(self) -> None:
        self.current_block = int(self.var_brush.get())
        self.draw_board()

    def move_selection(self, dx: int, dy: int) -> None:
        self.selected_col = ((self.selected_col + dx - 1) % self.stage.columns) + 1
        self.selected_row = max(1, min(self.stage.rows, self.selected_row + dy))
        self.draw_board()

    def set_brush_and_cell(self, value: int) -> None:
        self.current_block = value
        self.var_brush.set(value)
        self.set_selected_cell(value)

    def set_selected_cell(self, value: int) -> None:
        if self.stage.cells[self.selected_row - 1][self.selected_col - 1] == value:
            return
        self.push_undo_state()
        self.stage.cells[self.selected_row - 1][self.selected_col - 1] = value
        self.one_move_candidates = []
        self.refresh_and_draw()

    def cycle_selected_cell(self) -> None:
        current = self.stage.cells[self.selected_row - 1][self.selected_col - 1]
        next_value = (current + 1) % 5
        self.current_block = next_value
        self.var_brush.set(next_value)
        self.set_selected_cell(next_value)

    # ------------------------------------------------------------------ Editing

    def apply_resize(self) -> None:
        try:
            columns = int(self.var_columns.get())
            rows = int(self.var_rows.get())
        except Exception:
            messagebox.showerror("エラー", "columns/rows は整数で指定してください。")
            return

        if not (4 <= columns <= 24 and 3 <= rows <= 12):
            messagebox.showerror("エラー", "columns は4〜24、rows は3〜12の範囲にしてください。")
            return

        self.push_undo_state()

        self.stage.columns = columns
        self.stage.rows = rows
        self.stage.ensure_cells()
        self.selected_col = min(self.selected_col, columns)
        self.selected_row = min(self.selected_row, rows)
        self.refresh_and_draw()

    def clear_board(self) -> None:
        self.push_undo_state()
        self.stage.cells = [[BlockType.EMPTY for _ in range(self.stage.columns)] for _ in range(self.stage.rows)]
        self.one_move_candidates = []
        self.refresh_and_draw()

    def randomize_board(self) -> None:
        self.push_undo_state()
        for r in range(self.stage.rows):
            for c in range(self.stage.columns):
                self.stage.cells[r][c] = random.choice([BlockType.SLASH, BlockType.BACKSLASH, BlockType.VALLEY, BlockType.PEAK])
        self.one_move_candidates = []
        self.refresh_and_draw()

    def rotate_columns(self, direction: int) -> None:
        # direction = 1: 右へ、-1: 左へ
        self.push_undo_state()
        for r in range(self.stage.rows):
            row = self.stage.cells[r]
            if direction > 0:
                self.stage.cells[r] = [row[-1]] + row[:-1]
            else:
                self.stage.cells[r] = row[1:] + [row[0]]
        self.one_move_candidates = []
        self.refresh_and_draw()

    def shift_column(self, direction: int) -> None:
        self.push_undo_state()
        col = self.selected_col - 1
        values = [self.stage.cells[r][col] for r in range(self.stage.rows)]
        if direction > 0:
            values = [values[-1]] + values[:-1]
        else:
            values = values[1:] + [values[0]]
        for r in range(self.stage.rows):
            self.stage.cells[r][col] = values[r]
        self.one_move_candidates = []
        self.refresh_and_draw()

    # ------------------------------------------------------------------ Analysis

    def get_logic(self) -> BoardLogic:
        return BoardLogic(self.stage.columns, self.stage.rows, self.stage.cells)

    def refresh_analysis(self) -> None:
        logic = self.get_logic()
        groups = logic.check_erase_groups()
        self.erase_coords = set()
        for group in groups:
            for index in group:
                self.erase_coords.add(logic.index_to_cell(index))

        filled = sum(1 for row in self.stage.cells for v in row if v != BlockType.EMPTY)
        empty = self.stage.columns * self.stage.rows - filled
        wrap_used = self.has_wrap_loop(groups, logic)

        info = []
        info.append(f"サイズ: {self.stage.columns} x {self.stage.rows}")
        info.append(f"配置済み: {filled} / 空白: {empty}")
        info.append(f"消去グループ数: {len(groups)}")
        info.append(f"消去パネル数: {len(self.erase_coords)}")
        info.append(f"左右またぎを含む可能性: {'あり' if wrap_used else 'なし'}")
        if self.one_move_candidates:
            info.append(f"1手消去候補: {len(self.one_move_candidates)}")
            preview = ", ".join(f"({c},{r})" for c, r in self.one_move_candidates[:12])
            info.append(preview + (" ..." if len(self.one_move_candidates) > 12 else ""))
        else:
            info.append("1手消去候補: 未計算")

        if groups:
            info.append("")
            info.append("消去グループ:")
            for i, group in enumerate(groups, start=1):
                coords = [logic.index_to_cell(index) for index in group]
                info.append(f"  {i}: {len(group)}枚 {coords}")

        self.info_text.configure(state=tk.NORMAL)
        self.info_text.delete("1.0", tk.END)
        self.info_text.insert(tk.END, "\n".join(info))
        self.info_text.configure(state=tk.DISABLED)

    def has_wrap_loop(self, groups: List[List[int]], logic: BoardLogic) -> bool:
        """
        厳密な幾何判定ではなく、消去対象セルが1列目と最終列の両方にまたがる場合を
        左右またぎ候補として扱う。
        """
        for group in groups:
            cols = {logic.index_to_cell(index)[0] for index in group}
            if 1 in cols and self.stage.columns in cols:
                return True
        return False

    def refresh_and_draw(self) -> None:
        self.refresh_analysis()
        self.draw_board()

    def show_one_move_candidates(self) -> None:
        self.one_move_candidates = self.get_logic().one_move_loop_candidates()
        self.refresh_and_draw()

    # ------------------------------------------------------------------ Test play

    def open_test_play_mode(self) -> None:
        start_row = max(2, self.selected_row)
        TestPlayWindow(self, self.stage, self.selected_col, start_row)

    # ------------------------------------------------------------------ Stage conversion

    def sync_stage_from_ui(self) -> None:
        self.stage.stage_id = self.var_stage_id.get().strip() or "stage_001"
        self.stage.name = self.var_name.get().strip() or self.stage.stage_id
        self.stage.pack = self.var_pack.get().strip() or "default"
        self.stage.rules.manual_rise_enabled = bool(self.var_manual_rise.get())
        self.stage.rules.auto_rise_enabled = bool(self.var_auto_rise.get())

        move_limit_text = self.var_move_limit.get().strip()
        self.stage.rules.move_limit = int(move_limit_text) if move_limit_text else None

        clear_count_text = self.var_clear_count.get().strip()
        self.stage.clear_condition.type = self.clear_condition_internal_value(self.var_clear_type.get().strip() or "全消し")
        self.stage.clear_condition.count = int(clear_count_text) if clear_count_text else None

    def sync_ui_from_stage(self) -> None:
        self.var_stage_id.set(self.stage.stage_id)
        self.var_name.set(self.stage.name)
        self.var_pack.set(self.stage.pack)
        self.var_columns.set(self.stage.columns)
        self.var_rows.set(self.stage.rows)
        self.var_move_limit.set("" if self.stage.rules.move_limit is None else str(self.stage.rules.move_limit))
        self.var_clear_type.set(self.clear_condition_display_value(self.stage.clear_condition.type))
        self.var_clear_count.set("" if self.stage.clear_condition.count is None else str(self.stage.clear_condition.count))
        self.var_manual_rise.set(self.stage.rules.manual_rise_enabled)
        self.var_auto_rise.set(self.stage.rules.auto_rise_enabled)

    def to_json_dict(self) -> dict:
        self.sync_stage_from_ui()
        return {
            "version": self.stage.version,
            "id": self.stage.stage_id,
            "name": self.stage.name,
            "pack": self.stage.pack,
            "board": {
                "columns": self.stage.columns,
                "rows": self.stage.rows,
                "cells": self.stage.cells,
            },
            "rules": {
                "moveLimit": self.stage.rules.move_limit,
                "timeLimit": self.stage.rules.time_limit,
                "manualRiseEnabled": self.stage.rules.manual_rise_enabled,
                "autoRiseEnabled": self.stage.rules.auto_rise_enabled,
                "autoRiseInterval": self.stage.rules.auto_rise_interval,
            },
            "riseQueue": self.stage.rise_queue,
            "clearCondition": {
                "type": self.stage.clear_condition.type,
                "count": self.stage.clear_condition.count,
                "mark": self.stage.clear_condition.mark,
            },
            "notes": self.stage.notes,
        }

    def load_from_json_dict(self, data: dict, clear_history: bool = True) -> None:
        board = data.get("board", {})
        rules = data.get("rules", {})
        clear = data.get("clearCondition", {})

        self.stage = StageData(
            version=int(data.get("version", 1)),
            stage_id=str(data.get("id", "stage_001")),
            name=str(data.get("name", "First Loop")),
            pack=str(data.get("pack", "tutorial")),
            columns=int(board.get("columns", 10)),
            rows=int(board.get("rows", 6)),
            cells=board.get("cells", []),
            rules=StageRules(
                move_limit=rules.get("moveLimit", 10),
                time_limit=rules.get("timeLimit"),
                manual_rise_enabled=bool(rules.get("manualRiseEnabled", True)),
                auto_rise_enabled=bool(rules.get("autoRiseEnabled", False)),
                auto_rise_interval=rules.get("autoRiseInterval"),
            ),
            clear_condition=ClearCondition(
                type=str(clear.get("type", "eraseAll")),
                count=clear.get("count"),
                mark=clear.get("mark"),
            ),
            rise_queue=data.get("riseQueue", []),
            notes=str(data.get("notes", "")),
        )
        self.stage.ensure_cells()
        self.selected_col = min(max(self.selected_col, 1), self.stage.columns)
        self.selected_row = min(max(self.selected_row, 1), self.stage.rows)
        self.sync_ui_from_stage()
        self.one_move_candidates = []
        self.refresh_and_draw()
        if clear_history:
            self.clear_undo_redo_history()

    # ------------------------------------------------------------------ File I/O
	# 名前をつけて保存.
    def save_json(self) -> None:
		# 保存ファイルダイアログを表示.
        path = filedialog.asksaveasfilename(
            defaultextension=".json",
            filetypes=[("JSON", "*.json"), ("All files", "*.*")],
            initialfile=f"{self.stage.stage_id}.json",
        )
        if not path:
            return # キャンセルされた場合は何もしない.
        self.save_json_to_path(path)

	# 保存ダイアログなしで上書き保存.
    def save_json_overwrite(self) -> None:
        if not self.last_saved_path:
            self.save_json()  # 保存ダイアログを表示して保存.
            return
        self.save_json_to_path(self.last_saved_path)

    # jsonの読み込み.
    def load_json(self) -> None:
        path = filedialog.askopenfilename(filetypes=[("JSON", "*.json"), ("All files", "*.*")])
        if not path:
            return
        self.load_json_from_path(path)
    # Luaに書き出す.
    def export_lua(self) -> None:
        try:
            lua = self.to_lua_string()
        except Exception as exc:
            messagebox.showerror("エラー", f"Lua出力に失敗しました。\n{exc}")
            return

        path = filedialog.asksaveasfilename(
            defaultextension=".lua",
            filetypes=[("Lua", "*.lua"), ("All files", "*.*")],
            initialfile=f"{self.stage.stage_id}.lua",
        )
        if not path:
            return
        with open(path, "w", encoding="utf-8") as f:
            f.write(lua)
    # Lua文字列をクリップボードにコピーする.
    def copy_lua_to_clipboard(self) -> None:
        try:
            lua = self.to_lua_string()
        except Exception as exc:
            messagebox.showerror("エラー", f"Lua変換に失敗しました。\n{exc}")
            return
        self.clipboard_clear()
        self.clipboard_append(lua)
        messagebox.showinfo("コピー完了", "Luaステージデータをクリップボードへコピーしました。")

    def to_lua_string(self) -> str:
        self.sync_stage_from_ui()

        def lua_value(v) -> str:
            if v is None:
                return "nil"
            if isinstance(v, bool):
                return "true" if v else "false"
            if isinstance(v, (int, float)):
                return str(v)
            s = str(v).replace("\\", "\\\\").replace('"', '\\"')
            return f'"{s}"'

        lines: List[str] = []
        lines.append("-- Auto-generated by pd_mawaru_level_editor.py")
        lines.append("return {")
        lines.append(f"    version = {self.stage.version},")
        lines.append(f"    id = {lua_value(self.stage.stage_id)},")
        lines.append(f"    name = {lua_value(self.stage.name)},")
        lines.append(f"    pack = {lua_value(self.stage.pack)},")
        lines.append("")
        lines.append("    board = {")
        lines.append(f"        columns = {self.stage.columns},")
        lines.append(f"        rows = {self.stage.rows},")
        lines.append("        cells = {")
        for row in self.stage.cells:
            values = ",".join(str(int(v)) for v in row)
            comment = " ".join(BLOCK_SHORT[int(v)] for v in row)
            lines.append(f"            {{{values}}}, -- {comment}")
        lines.append("        },")
        lines.append("    },")
        lines.append("")
        lines.append("    rules = {")
        lines.append(f"        moveLimit = {lua_value(self.stage.rules.move_limit)},")
        lines.append(f"        timeLimit = {lua_value(self.stage.rules.time_limit)},")
        lines.append(f"        manualRiseEnabled = {lua_value(self.stage.rules.manual_rise_enabled)},")
        lines.append(f"        autoRiseEnabled = {lua_value(self.stage.rules.auto_rise_enabled)},")
        lines.append(f"        autoRiseInterval = {lua_value(self.stage.rules.auto_rise_interval)},")
        lines.append("    },")
        lines.append("")
        lines.append("    clearCondition = {")
        lines.append(f"        type = {lua_value(self.stage.clear_condition.type)},")
        lines.append(f"        count = {lua_value(self.stage.clear_condition.count)},")
        lines.append(f"        mark = {lua_value(self.stage.clear_condition.mark)},")
        lines.append("    },")

        if self.stage.rise_queue:
            lines.append("")
            lines.append("    riseQueue = {")
            for row in self.stage.rise_queue:
                values = ",".join(str(int(v)) for v in row)
                lines.append(f"        {{{values}}},")
            lines.append("    },")

        if self.stage.notes:
            lines.append("")
            lines.append(f"    notes = {lua_value(self.stage.notes)},")

        lines.append("}")
        lines.append("")
        return "\n".join(lines)


def main() -> None:
    if TK_IMPORT_ERROR is not None:
        print("tkinter を読み込めませんでした。", file=sys.stderr)
        print("このレベルエディタは Tk 対応の Python が必要です。", file=sys.stderr)
        print("確認: python3 -m tkinter", file=sys.stderr)
        print(f"詳細: {TK_IMPORT_ERROR}", file=sys.stderr)
        sys.exit(1)

    app = LevelEditor()
    app.mainloop()


if __name__ == "__main__":
    main()
