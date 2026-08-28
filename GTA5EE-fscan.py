#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import time
import configparser
import shutil
import webbrowser
from pathlib import Path

# 依赖自动检测与安装
def ensure_dependencies():
    required = []
    missing = []
    for pkg in required:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print(f"[提示] 正在安装缺失依赖: {', '.join(missing)}")
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "--quiet"] + missing)
        print("[完成] 依赖安装成功\n")

ensure_dependencies()

def set_console_title():
    if sys.platform.startswith("win"):
        try:
            import ctypes
            ctypes.windll.kernel32.SetConsoleTitleW("Grand Theft Auto V Enhanced File Scanner")
        except Exception:
            os.system("title Grand Theft Auto V Enhanced File Scanner")
    else:
        print("\033]0;Grand Theft Auto V Enhanced File Scanner\007", end="", flush=True)

set_console_title()

# 彩色输出
class Color:
    """ANSI 颜色码（Windows 10+ / Linux / macOS 均支持）"""
    RESET   = "\033[0m"
    BOLD    = "\033[1m"
    DIM     = "\033[2m"
    # 前景色
    BLACK   = "\033[30m"
    RED     = "\033[31m"
    GREEN   = "\033[32m"
    YELLOW  = "\033[33m"
    BLUE    = "\033[34m"
    MAGENTA = "\033[35m"
    CYAN    = "\033[36m"
    WHITE   = "\033[37m"
    # 亮色
    LRED    = "\033[91m"
    LGREEN  = "\033[92m"
    LYELLOW = "\033[93m"
    LBLUE   = "\033[94m"
    LMAGENTA= "\033[95m"
    LCYAN   = "\033[96m"
    LWHITE  = "\033[97m"
    # 背景
    BG_RED  = "\033[41m"
    BG_GREEN= "\033[42m"
    BG_YELLOW = "\033[43m"

def enable_windows_ansi():
    """Windows 下开启 ANSI 颜色支持"""
    if sys.platform.startswith("win"):
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32
            # 启用虚拟终端处理
            handle = kernel32.GetStdHandle(-11)  # STD_OUTPUT_HANDLE
            mode = ctypes.c_ulong()
            kernel32.GetConsoleMode(handle, ctypes.byref(mode))
            kernel32.SetConsoleMode(handle, mode.value | 0x0004)  # ENABLE_VIRTUAL_TERMINAL_PROCESSING
        except Exception:
            pass

enable_windows_ansi()

def cprint(text, color=Color.RESET, end="\n", bold=False):
    """带颜色的 print"""
    prefix = Color.BOLD + color if bold else color
    print(f"{prefix}{text}{Color.RESET}", end=end, flush=True)

def ok(msg):    cprint(f"[成功] {msg}", Color.LGREEN)
def info(msg):  cprint(f"[提示] {msg}", Color.LCYAN)
def warn(msg):  cprint(f"[警告] {msg}", Color.LYELLOW)
def err(msg):   cprint(f"[错误] {msg}", Color.LRED)
def title(msg): cprint(msg, Color.LCYAN, bold=True)
def high(msg):  cprint(msg, Color.LRED, bold=True)

# 全局配置
SCRIPT_DIR = Path(__file__).resolve().parent
DIR_LIST_FILE = SCRIPT_DIR / "GTA-Directory.txt"
PATH_INI_FILE = SCRIPT_DIR / "GTA-Path.ini"
SECTION = "GTA"
KEY_PATH = "path"

IS_WINDOWS = sys.platform.startswith("win")

def getch():
    """读取单个字符（无需回车）"""
    if IS_WINDOWS:
        import msvcrt
        ch = msvcrt.getch()
        try:
            return ch.decode("utf-8", errors="ignore")
        except Exception:
            return ch.decode("gbk", errors="ignore")
    else:
        import tty
        import termios
        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            ch = sys.stdin.read(1)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
        return ch


# 路径管理
def load_gta_path() -> Path | None:
    if not PATH_INI_FILE.exists():
        return None
    cfg = configparser.ConfigParser()
    try:
        cfg.read(PATH_INI_FILE, encoding="utf-8")
        path_str = cfg.get(SECTION, KEY_PATH, fallback="").strip()
        if path_str and Path(path_str).exists():
            return Path(path_str)
    except Exception:
        pass
    return None


def save_gta_path(path: Path):
    cfg = configparser.ConfigParser()
    cfg[SECTION] = {KEY_PATH: str(path.resolve())}
    with open(PATH_INI_FILE, "w", encoding="utf-8") as f:
        cfg.write(f)
    ok(f"路径已保存到 {PATH_INI_FILE.name}")


def ask_gta_path() -> Path:
    cprint("\n请输入 GTA V Enhanced 的完整安装路径", Color.LYELLOW)
    cprint(r"例如：C:\Steam\steamapps\common\Grand Theft Auto V Enhanced", Color.DIM)
    cprint("输入后按回车确认：", Color.WHITE)
    while True:
        try:
            path_str = input("> ").strip().strip('"').strip("'")
            if not path_str:
                err("路径不能为空，请重新输入。")
                continue
            p = Path(path_str)
            if not p.exists():
                err(f"路径不存在：{p}")
                continue
            if not p.is_dir():
                err(f"这不是一个文件夹：{p}")
                continue
            markers = ["GTA5_Enhanced.exe", "GTA5.exe", "PlayGTAV.exe", "common.rpf"]
            found = any((p / m).exists() for m in markers)
            if not found:
                warn("此目录下未检测到常见 GTA 可执行文件/资源，确定要使用吗？(y/n)")
                confirm = input("> ").strip().lower()
                if confirm not in ("y", "yes", "是"):
                    continue
            return p
        except KeyboardInterrupt:
            print()
            err("用户中断")
            sys.exit(0)
        except Exception as e:
            err(str(e))


# 解析官方目录列表
def parse_official_list_v2(list_file: Path) -> set[str]:
    official = set()
    if not list_file.exists():
        return official

    stack = []
    with open(list_file, "r", encoding="utf-8", errors="ignore") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip("\r\n")
            if not line.strip():
                continue

            if lineno == 1 and not any(x in line for x in ("|", "+", "\\")):
                continue

            is_dir = False
            name = ""
            if "+---" in line:
                is_dir = True
                name = line.split("+---")[-1].strip()
            elif "\\---" in line:
                is_dir = True
                name = line.split("\\---")[-1].strip()
            else:
                if "|" in line:
                    name = line.split("|")[-1].strip()
                else:
                    name = line.strip()

            if not name:
                continue

            leading = 0
            for ch in line:
                if ch in " |+\\-":
                    leading += 1
                else:
                    break
            level = max(0, leading // 4)

            while stack and stack[-1][0] >= level:
                stack.pop()

            if is_dir:
                stack.append((level, name))
            else:
                parts = [s[1] for s in stack] + [name]
                rel = "/".join(parts).lower().replace("\\", "/")
                official.add(rel)

    return official


# 扫描实际目录
def scan_real_directory(root: Path) -> set[str]:
    real_files = set()
    root = root.resolve()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".git", "__pycache__", "System Volume Information")]
        for fn in filenames:
            full = Path(dirpath) / fn
            try:
                rel = full.relative_to(root).as_posix().lower()
                real_files.add(rel)
            except ValueError:
                continue
    return real_files


# 高风险关键词
HIGH_RISK_KEYWORDS = (
    ".asi", "xinput", "dinput8", "winmm", "dsound", "version.dll",
    "scripthook", "menyoo", "trainer", "modmenu", "cheat", "hack",
    "inject", "openiv", "script", "native", "bypass", "spoof"
)

def is_high_risk(filename: str) -> bool:
    f = filename.lower()
    return any(k in f for k in HIGH_RISK_KEYWORDS)


# 对比与报告
def compare_and_report(official: set[str], real: set[str], gta_root: Path):
    extra = sorted(real - official)
    missing = sorted(official - real)

    print()
    cprint("=" * 70, Color.LCYAN)
    title("                      扫描结果报告")
    cprint("=" * 70, Color.LCYAN)

    cprint(f"官方列表文件数 : ", Color.WHITE, end="")
    cprint(f"{len(official)}", Color.LGREEN, bold=True)
    cprint(f"实际目录文件数 : ", Color.WHITE, end="")
    cprint(f"{len(real)}", Color.LGREEN, bold=True)
    cprint(f"多余文件数量   : ", Color.WHITE, end="")
    cprint(f"{len(extra)}", Color.LRED if extra else Color.LGREEN, bold=True)
    cprint(f"  （可能是外挂/Mod/残留）", Color.DIM)
    cprint(f"缺失文件数量   : ", Color.WHITE, end="")
    cprint(f"{len(missing)}", Color.LYELLOW if missing else Color.LGREEN, bold=True)
    cprint(f" （官方有但本地没有）", Color.DIM)
    cprint("=" * 70, Color.LCYAN)

    high_risk_list = []

    if extra:
        print()
        cprint("【多余 / 可疑文件】", Color.LRED, bold=True)
        cprint("（建议删除或移走后再进 Online）", Color.DIM)
        cprint("-" * 70, Color.DIM)

        for i, f in enumerate(extra, 1):
            full = gta_root / f.replace("/", os.sep)
            size = ""
            try:
                if full.exists():
                    size = f"  ({full.stat().st_size / 1024:.1f} KB)"
            except Exception:
                pass

            if is_high_risk(f):
                high_risk_list.append(f)
                cprint(f"  {i:3d}. ", Color.WHITE, end="")
                cprint(f"{f}{size}", Color.LRED, bold=True)
            else:
                cprint(f"  {i:3d}. ", Color.WHITE, end="")
                cprint(f"{f}{size}", Color.LYELLOW)

        cprint("-" * 70, Color.DIM)
        cprint(f"共 {len(extra)} 个多余文件。", Color.LRED)

        if high_risk_list:
            print()
            cprint("★★★ 高风险可疑文件（强烈建议立即删除）★★★", Color.BG_RED + Color.LWHITE, bold=True)
            for f in high_risk_list:
                cprint(f"  → {f}", Color.LRED, bold=True)
    else:
        print()
        ok("未发现多余文件，目录看起来很干净。")

    if missing and len(missing) < 50:
        print()
        cprint("【缺失的官方文件】", Color.LYELLOW, bold=True)
        cprint("（可运行启动器“验证游戏文件完整性”修复）", Color.DIM)
        cprint("-" * 70, Color.DIM)
        for i, f in enumerate(missing[:30], 1):
            cprint(f"  {i:3d}. {f}", Color.LYELLOW)
        if len(missing) > 30:
            cprint(f"  ... 还有 {len(missing) - 30} 个", Color.DIM)
    elif missing:
        warn(f"有 {len(missing)} 个官方文件缺失，建议在 Rockstar/Steam 启动器中验证游戏文件。")

    print()
    ok("扫描完成。")
    return extra, missing, high_risk_list


# 删除功能
def ask_delete_files(extra: list, high_risk: list, gta_root: Path):
    """询问用户是否删除多余文件"""
    if not extra:
        return

    print()
    cprint("=" * 70, Color.LYELLOW)
    cprint("是否要删除上面的多余文件？", Color.LYELLOW, bold=True)
    cprint("=" * 70, Color.LYELLOW)
    cprint("  Y / y  → 删除全部多余文件", Color.LRED)
    cprint("  H / h  → 只删除高风险文件（推荐）", Color.LRED)
    cprint("  N / n  → 不删除，返回菜单", Color.LGREEN)
    cprint("请选择（无需回车）：", Color.WHITE, end="")

    while True:
        choice = getch().strip().lower()
        print(choice)

        if choice in ("n", "no", "否"):
            info("已取消删除。")
            return

        if choice in ("y", "yes", "是"):
            targets = extra
            break

        if choice in ("h",):
            if not high_risk:
                warn("没有检测到高风险文件。")
                return
            targets = high_risk
            break

        err("无效选项，请按 Y / H / N")
        cprint("请选择（无需回车）：", Color.WHITE, end="")

    # 二次确认
    print()
    cprint(f"即将删除 {len(targets)} 个文件，此操作不可恢复！", Color.LRED, bold=True)
    cprint("确认删除请再按一次 Y，取消请按 N：", Color.LYELLOW, end="")
    confirm = getch().strip().lower()
    print(confirm)

    if confirm not in ("y", "yes", "是"):
        info("已取消删除。")
        return

    # 开始删除
    print()
    cprint("正在删除...", Color.LCYAN)
    success = 0
    failed = 0
    deleted_list = []

    for rel in targets:
        full = gta_root / rel.replace("/", os.sep)
        try:
            if full.exists():
                if full.is_file():
                    full.unlink()
                elif full.is_dir():
                    shutil.rmtree(full)
                cprint(f"  ✓ 已删除: {rel}", Color.LGREEN)
                success += 1
                deleted_list.append(rel)
            else:
                cprint(f"  - 不存在: {rel}", Color.DIM)
        except Exception as e:
            cprint(f"  ✗ 删除失败: {rel}  →  {e}", Color.LRED)
            failed += 1

    print()
    cprint("=" * 50, Color.LCYAN)
    ok(f"成功删除 {success} 个文件")
    if failed:
        err(f"失败 {failed} 个文件（可能被占用，请关闭游戏后再试）")
    cprint("=" * 50, Color.LCYAN)

    if deleted_list:
        # 简单备份记录
        log_file = SCRIPT_DIR / "deleted_files_log.txt"
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(f"\n===== {time.strftime('%Y-%m-%d %H:%M:%S')} =====\n")
            for item in deleted_list:
                f.write(item + "\n")
        info(f"删除记录已保存到 {log_file.name}")


# 主菜单
def clear_screen():
    os.system("cls" if IS_WINDOWS else "clear")


def show_menu(gta_path: Path | None):
    clear_screen()
    cprint("=" * 60, Color.LCYAN)
    cprint("       Grand Theft Auto V Enhanced 文件扫描器", Color.LCYAN, bold=True)
    cprint("=" * 60, Color.LCYAN)
    if gta_path:
        cprint("当前路径: ", Color.WHITE, end="")
        cprint(str(gta_path), Color.LGREEN)
    else:
        cprint("当前路径: ", Color.WHITE, end="")
        cprint("未设置", Color.LRED)
    cprint("-" * 60, Color.DIM)
    cprint("  1. ", Color.LYELLOW, end="")
    cprint("★开始扫描目录文件★", Color.LWHITE)
    cprint("  2. ", Color.LYELLOW, end="")
    cprint("重新设定 GTA 路径", Color.LWHITE)
    cprint("  3. ", Color.LYELLOW, end="")
    cprint("打开纯净目录清单", Color.LWHITE)
    cprint("  4. ", Color.LYELLOW, end="")
    cprint("打开当前 GTA 目录", Color.LWHITE)
    cprint("  5. ", Color.LYELLOW, end="")
    cprint("更新此脚本", Color.LWHITE)
    cprint("  0. ", Color.LYELLOW, end="")
    cprint("退出", Color.LWHITE)
    cprint("-" * 60, Color.DIM)
    cprint("请按数字键选择：", Color.LCYAN, end="")


def open_file(path: Path):
    if not path.exists():
        err(f"文件不存在: {path}")
        return
    try:
        if IS_WINDOWS:
            os.startfile(str(path))
        elif sys.platform == "darwin":
            os.system(f'open "{path}"')
        else:
            os.system(f'xdg-open "{path}"')
        ok(f"已打开 {path.name}")
    except Exception as e:
        err(f"无法打开: {e}")


def open_folder(path: Path):
    if not path.exists():
        err(f"目录不存在: {path}")
        return
    try:
        if IS_WINDOWS:
            os.startfile(str(path))
        elif sys.platform == "darwin":
            os.system(f'open "{path}"')
        else:
            os.system(f'xdg-open "{path}"')
        ok(f"已打开 {path}")
    except Exception as e:
        err(f"无法打开: {e}")


def main():
    if not DIR_LIST_FILE.exists():
        cprint("=" * 60, Color.LRED)
        err("GTA-Directory.txt 目录文件不存在！")
        cprint(f"请把纯净文件清单放到脚本同级目录：", Color.LYELLOW)
        cprint(f"  {DIR_LIST_FILE}", Color.LWHITE)
        cprint("=" * 60, Color.LRED)
        cprint("按任意键退出...", Color.DIM)
        getch()
        return

    gta_path = load_gta_path()
    if gta_path is None:
        info("首次运行或路径文件丢失，需要设置 GTA 路径")
        gta_path = ask_gta_path()
        save_gta_path(gta_path)

    while True:
        show_menu(gta_path)
        try:
            choice = getch().strip()
        except KeyboardInterrupt:
            print("\n")
            info("再见！")
            break

        if choice == "1":
            clear_screen()
            info("正在解析官方干净列表...")
            official = parse_official_list_v2(DIR_LIST_FILE)
            if not official:
                err("官方列表解析失败或为空，请检查 GTA-Directory.txt 格式。")
                cprint("按任意键返回菜单...", Color.DIM)
                getch()
                continue

            ok(f"官方列表解析完成，共 {len(official)} 个文件。")
            cprint(f"正在扫描实际目录：{gta_path}", Color.LCYAN)
            cprint("（目录较大时可能需要几秒到几十秒，请耐心等待...）", Color.DIM)
            start = time.time()
            real = scan_real_directory(gta_path)
            elapsed = time.time() - start
            ok(f"扫描完成，用时 {elapsed:.1f} 秒，共发现 {len(real)} 个文件。")

            extra, missing, high_risk = compare_and_report(official, real, gta_path)

            # 询问是否删除
            if extra:
                ask_delete_files(extra, high_risk, gta_path)

            print()
            cprint("按任意键返回菜单...", Color.DIM)
            getch()

        elif choice == "2":
            clear_screen()
            info("重新设定路径：")
            new_path = ask_gta_path()
            save_gta_path(new_path)
            gta_path = new_path
            cprint("按任意键返回菜单...", Color.DIM)
            getch()

        elif choice == "3":
            clear_screen()
            open_file(DIR_LIST_FILE)
            cprint("按任意键返回菜单...", Color.DIM)
            getch()

        elif choice == "4":
            clear_screen()
            if gta_path and gta_path.exists():
                open_folder(gta_path)
            else:
                err("路径无效")
            cprint("按任意键返回菜单...", Color.DIM)
            getch()

        elif choice == "5":
            clear_screen()
            webbrowser.open("https://github.com/NeetheCheeBao/GTA5EE-FS")
            ok("已在浏览器打开更新页面。")
            cprint("按任意键返回菜单...", Color.DIM)
            getch()

        elif choice in ("0", "q", "Q", "\x03"):
            clear_screen()
            cprint("再见！祝你游戏愉快，远离封禁。", Color.LGREEN, bold=True)
            break

        else:
            warn("无效选项，请重新选择。")
            time.sleep(0.8)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print()
        err(f"致命错误: {e}")
        import traceback
        traceback.print_exc()
        cprint("\n按任意键退出...", Color.DIM)
        try:
            getch()
        except Exception:
            input()