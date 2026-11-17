@echo off
goto :GTAFS_START
rem ============================================================
rem  GTA5EE-FileScanner.bat
rem  双击即可运行。启动器会把当前控制台交给 Windows PowerShell，
rem  PowerShell 源码内嵌在本文件末尾的标记行之后。
rem  请勿修改标记行以上的任何内容。
rem ============================================================
:GTAFS_START
setlocal
set "GTAFS_SELF=%~f0"
title Grand Theft Auto V Enhanced File Scanner
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:GTAFS_SELF; $t=[IO.File]::ReadAllText($p,[Text.Encoding]::UTF8); $tag=[char]35+'__PS_BEGIN__'; $i=$t.LastIndexOf($tag); if($i -lt 0){Write-Host 'Launcher: code marker not found.' -ForegroundColor Red; exit 1}; $c=$t.Substring($i+$tag.Length); Invoke-Expression $c"
set "GTAFS_RC=%ERRORLEVEL%"
if not "%GTAFS_RC%"=="0" (
    echo.
    echo [Launcher] PowerShell exited with code %GTAFS_RC%.
    pause
)
exit /b %GTAFS_RC%

rem ------------------------------------------------------------
rem  PowerShell source begins at the marker line below.
rem ------------------------------------------------------------
#__PS_BEGIN__
# ============================================================
#  Grand Theft Auto V Enhanced File Scanner
#  PowerShell 5.1
# ============================================================

$ErrorActionPreference = 'Continue'

# ---------- 脚本所在目录 ----------
if ($env:GTAFS_SELF -and (Test-Path -LiteralPath $env:GTAFS_SELF)) {
    $script:ScriptDir = Split-Path -Parent $env:GTAFS_SELF
} elseif ($PSScriptRoot) {
    $script:ScriptDir = $PSScriptRoot
} else {
    $script:ScriptDir = (Get-Location).Path
}

$script:DirListFile = Join-Path $script:ScriptDir 'GTA-Directory.txt'
$script:PathIniFile = Join-Path $script:ScriptDir 'GTA-Path.ini'
$script:LogFile     = Join-Path $script:ScriptDir 'deleted_files_log.txt'
$script:UpdateUrl   = 'https://github.com/NeetheCheeBao/GTA5EE-FS'
$script:Utf8NoBom   = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)

# 高风险关键词
$script:HighRiskKeywords = @(
    '.asi', 'xinput', 'dinput8', 'winmm', 'dsound', 'version.dll',
    'scripthook', 'menyoo', 'trainer', 'modmenu', 'cheat', 'hack',
    'inject', 'openiv', 'script', 'native', 'bypass', 'spoof'
)

try { $Host.UI.RawUI.WindowTitle = 'Grand Theft Auto V Enhanced File Scanner' } catch { }

# ============================================================
#  输出辅助
# ============================================================
function Write-C {
    param(
        [Parameter(Position = 0)][string]$Text = '',
        [Parameter(Position = 1)][ConsoleColor]$Color = [ConsoleColor]::Gray,
        [switch]$NoNewline
    )
    if ($NoNewline) {
        Write-Host $Text -ForegroundColor $Color -NoNewline
    } else {
        Write-Host $Text -ForegroundColor $Color
    }
}

function Write-Ok   { param([string]$Msg) Write-C "[成功] $Msg" Green }
function Write-Info { param([string]$Msg) Write-C "[提示] $Msg" Cyan }
function Write-Warn { param([string]$Msg) Write-C "[警告] $Msg" Yellow }
function Write-Err  { param([string]$Msg) Write-C "[错误] $Msg" Red }

function Read-Key {
    try {
        return [string][Console]::ReadKey($true).KeyChar
    } catch {
        return ''
    }
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    return ('{0:N1} KB' -f ($Bytes / 1KB))
}

# ============================================================
#  路径配置读写（GTA-Path.ini）
# ============================================================
function Get-SavedGtaPath {
    if (-not (Test-Path -LiteralPath $script:PathIniFile -PathType Leaf)) { return $null }
    try {
        $lines = [IO.File]::ReadAllLines($script:PathIniFile, [Text.Encoding]::UTF8)
        foreach ($line in $lines) {
            if ($line -match '^\s*path\s*=\s*(.+)$') {
                $p = $Matches[1].Trim().Trim('"').Trim("'")
                if ($p -and (Test-Path -LiteralPath $p -PathType Container)) { return $p }
            }
        }
    } catch { }
    return $null
}

function Set-SavedGtaPath {
    param([string]$Path)
    try {
        $full = [IO.Path]::GetFullPath($Path)
        $text = "[GTA]`r`npath = $full`r`n"
        [IO.File]::WriteAllText($script:PathIniFile, $text, $script:Utf8NoBom)
        Write-Ok "路径已保存到 $(Split-Path -Leaf $script:PathIniFile)"
    } catch {
        Write-Err "保存路径失败：$($_.Exception.Message)"
    }
}

function Read-GtaPath {
    Write-C ''
    Write-C '请输入 GTA V Enhanced 的完整安装路径' Yellow
    Write-C '例如：C:\Steam\steamapps\common\Grand Theft Auto V Enhanced' DarkGray
    Write-C '输入后按回车确认：' White

    while ($true) {
        Write-C '> ' Cyan -NoNewline
        $raw = Read-Host
        if ($null -eq $raw) { return $null }

        $p = $raw.Trim().Trim('"').Trim("'")
        if (-not $p) {
            Write-Err '路径不能为空，请重新输入。'
            continue
        }
        if (-not (Test-Path -LiteralPath $p)) {
            Write-Err "路径不存在：$p"
            continue
        }
        if (-not (Test-Path -LiteralPath $p -PathType Container)) {
            Write-Err "这不是一个文件夹：$p"
            continue
        }

        $markers = @('GTA5_Enhanced.exe', 'GTA5.exe', 'PlayGTAV.exe', 'common.rpf')
        $found = $false
        foreach ($m in $markers) {
            if (Test-Path -LiteralPath (Join-Path $p $m)) { $found = $true; break }
        }
        if (-not $found) {
            Write-Warn '此目录下未检测到常见 GTA 可执行文件/资源，确定要使用吗？(y/n)'
            Write-C '> ' Cyan -NoNewline
            $ans = (Read-Host).Trim().ToLower()
            if ($ans -notin @('y', 'yes', '是')) { continue }
        }
        return $p
    }
}

# ============================================================
#  解析官方干净清单（tree /a /f 的树状结构）
# ============================================================
function Get-OfficialList {
    param([string]$File)

    $official = New-Object 'System.Collections.Generic.HashSet[string]'
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return $official }

    $lines = [IO.File]::ReadAllLines($File, [Text.Encoding]::UTF8)
    $stack = New-Object System.Collections.ArrayList
    $lineno = 0

    foreach ($line in $lines) {
        $lineno++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        # 第一行是标题（"Grand Theft Auto V Enhanced"），跳过
        if ($lineno -eq 1 -and -not ($line.Contains('|') -or $line.Contains('+') -or $line.Contains('\'))) {
            continue
        }

        $isDir = $false
        $name = ''

        $i = $line.LastIndexOf('+---')
        if ($i -ge 0) {
            $isDir = $true
            $name = $line.Substring($i + 4).Trim()
        } else {
            $i = $line.LastIndexOf('\---')
            if ($i -ge 0) {
                $isDir = $true
                $name = $line.Substring($i + 4).Trim()
            } else {
                $i = $line.LastIndexOf('|')
                if ($i -ge 0) {
                    $name = $line.Substring($i + 1).Trim()
                } else {
                    $name = $line.Trim()
                }
            }
        }

        if (-not $name) { continue }

        # 层级 = 行首树形字符数 / 4
        $leading = 0
        foreach ($ch in $line.ToCharArray()) {
            if ($ch -eq ' ' -or $ch -eq '|' -or $ch -eq '+' -or $ch -eq '\' -or $ch -eq '-') {
                $leading++
            } else {
                break
            }
        }
        $level = [int][Math]::Floor($leading / 4)
        if ($level -lt 0) { $level = 0 }

        while ($stack.Count -gt 0 -and $stack[$stack.Count - 1].Level -ge $level) {
            $stack.RemoveAt($stack.Count - 1)
        }

        if ($isDir) {
            [void]$stack.Add([pscustomobject]@{ Level = $level; Name = $name })
        } else {
            $parts = @()
            foreach ($item in $stack) { $parts += $item.Name }
            $parts += $name
            $rel = ($parts -join '/').ToLowerInvariant().Replace('\', '/')
            [void]$official.Add($rel)
        }
    }

    return $official
}

# ============================================================
#  扫描实际游戏目录
# ============================================================
function Get-RealFiles {
    param([string]$Root)

    $files = New-Object 'System.Collections.Generic.HashSet[string]'
    $sizes = New-Object 'System.Collections.Generic.Dictionary[string,long]'
    $rootFull = ([IO.Path]::GetFullPath($Root)).TrimEnd('\')
    $prefixLen = $rootFull.Length + 1
    $skipPattern = '(^|/)(\.git|__pycache__|System Volume Information)(/|$)'

    $items = Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        $full = $item.FullName
        if ($full.Length -le $prefixLen) { continue }
        $rel = $full.Substring($prefixLen).Replace('\', '/').ToLowerInvariant()
        if ($rel -match $skipPattern) { continue }
        [void]$files.Add($rel)
        $sizes[$rel] = $item.Length
    }

    return [pscustomobject]@{ Files = $files; Sizes = $sizes }
}

function Test-HighRisk {
    param([string]$Name)
    $n = $Name.ToLowerInvariant()
    foreach ($k in $script:HighRiskKeywords) {
        if ($n.Contains($k)) { return $true }
    }
    return $false
}

# ============================================================
#  对比并输出报告
# ============================================================
function Show-Report {
    param($Official, $Real, $Sizes, [string]$Root)

    $extraList = New-Object System.Collections.ArrayList
    foreach ($f in $Real) {
        if (-not $Official.Contains($f)) { [void]$extraList.Add($f) }
    }
    $missingList = New-Object System.Collections.ArrayList
    foreach ($f in $Official) {
        if (-not $Real.Contains($f)) { [void]$missingList.Add($f) }
    }

    $extra   = @($extraList)
    $missing = @($missingList)
    if ($extra.Count -gt 1)   { [Array]::Sort($extra, [System.StringComparer]::Ordinal) }
    if ($missing.Count -gt 1) { [Array]::Sort($missing, [System.StringComparer]::Ordinal) }

    Write-Host ''
    Write-C ('=' * 70) Cyan
    Write-C '                      扫描结果报告' Cyan
    Write-C ('=' * 70) Cyan

    Write-C '官方列表文件数 : ' White -NoNewline
    Write-C "$($Official.Count)" Green
    Write-C '实际目录文件数 : ' White -NoNewline
    Write-C "$($Real.Count)" Green
    Write-C '多余文件数量   : ' White -NoNewline
    if ($extra.Count -gt 0) { Write-C "$($extra.Count)" Red } else { Write-C "$($extra.Count)" Green }
    Write-C '  （可能是外挂/Mod/残留）' DarkGray
    Write-C '缺失文件数量   : ' White -NoNewline
    if ($missing.Count -gt 0) { Write-C "$($missing.Count)" Yellow } else { Write-C "$($missing.Count)" Green }
    Write-C ' （官方有但本地没有）' DarkGray
    Write-C ('=' * 70) Cyan

    $highRiskList = New-Object System.Collections.ArrayList

    if ($extra.Count -gt 0) {
        Write-Host ''
        Write-C '【多余 / 可疑文件】' Red
        Write-C '（建议删除或移走后再进 Online）' DarkGray
        Write-C ('-' * 70) DarkGray

        $idx = 0
        foreach ($f in $extra) {
            $idx++
            $sizeText = ''
            if ($Sizes.ContainsKey($f)) { $sizeText = '  (' + (Format-Size $Sizes[$f]) + ')' }

            Write-C ("  {0,3}. " -f $idx) White -NoNewline
            if (Test-HighRisk $f) {
                [void]$highRiskList.Add($f)
                Write-C "$f$sizeText" Red
            } else {
                Write-C "$f$sizeText" Yellow
            }
        }

        Write-C ('-' * 70) DarkGray
        Write-C "共 $($extra.Count) 个多余文件。" Red

        if ($highRiskList.Count -gt 0) {
            Write-Host ''
            Write-Host '★★★ 高风险可疑文件（强烈建议立即删除）★★★' -ForegroundColor White -BackgroundColor Red
            foreach ($f in $highRiskList) { Write-C "  → $f" Red }
        }
    } else {
        Write-Host ''
        Write-Ok '未发现多余文件，目录看起来很干净。'
    }

    if ($missing.Count -gt 0 -and $missing.Count -lt 50) {
        Write-Host ''
        Write-C '【缺失的官方文件】' Yellow
        Write-C '（可运行启动器“验证游戏文件完整性”修复）' DarkGray
        Write-C ('-' * 70) DarkGray
        $shown = 0
        foreach ($f in $missing) {
            if ($shown -ge 30) { break }
            $shown++
            Write-C ("  {0,3}. {1}" -f $shown, $f) Yellow
        }
        if ($missing.Count -gt 30) {
            Write-C "  ... 还有 $($missing.Count - 30) 个" DarkGray
        }
    } elseif ($missing.Count -ge 50) {
        Write-Warn "有 $($missing.Count) 个官方文件缺失，建议在 Rockstar/Steam 启动器中验证游戏文件。"
    }

    Write-Host ''
    Write-Ok '扫描完成。'

    return [pscustomobject]@{
        Extra    = $extra
        Missing  = $missing
        HighRisk = @($highRiskList)
    }
}

# ============================================================
#  删除多余文件
# ============================================================
function Invoke-DeleteFlow {
    param($Extra, $HighRisk, [string]$Root)

    if ($Extra.Count -eq 0) { return }

    Write-Host ''
    Write-C ('=' * 70) Yellow
    Write-C '是否要删除上面的多余文件？' Yellow
    Write-C ('=' * 70) Yellow
    Write-C '  Y / y  → 删除全部多余文件' Red
    Write-C '  H / h  → 只删除高风险文件（推荐）' Red
    Write-C '  N / n  → 不删除，返回菜单' Green

    $targets = $null
    while ($null -eq $targets) {
        Write-C '请选择（无需回车）：' White -NoNewline
        $ch = (Read-Key).ToLower()
        Write-Host $ch

        if ($ch -in @('n', 'no', '否')) {
            Write-Info '已取消删除。'
            return
        } elseif ($ch -in @('y', 'yes', '是')) {
            $targets = @($Extra)
        } elseif ($ch -eq 'h') {
            if ($HighRisk.Count -eq 0) {
                Write-Warn '没有检测到高风险文件。'
                return
            }
            $targets = @($HighRisk)
        } else {
            Write-Err '无效选项，请按 Y / H / N'
        }
    }

    Write-Host ''
    Write-C "即将删除 $($targets.Count) 个文件，此操作不可恢复！" Red
    Write-C '确认删除请再按一次 Y，取消请按 N：' Yellow -NoNewline
    $confirm = (Read-Key).ToLower()
    Write-Host $confirm

    if ($confirm -notin @('y', 'yes', '是')) {
        Write-Info '已取消删除。'
        return
    }

    Write-Host ''
    Write-C '正在删除...' Cyan

    $success = 0
    $failed = 0
    $deleted = New-Object System.Collections.ArrayList

    foreach ($rel in $targets) {
        $full = Join-Path $Root ($rel.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $full)) {
            Write-C "  - 不存在: $rel" DarkGray
            continue
        }
        try {
            Remove-Item -LiteralPath $full -Force -Recurse -ErrorAction Stop
            Write-C "  √ 已删除: $rel" Green
            $success++
            [void]$deleted.Add($rel)
        } catch {
            Write-C "  × 删除失败: $rel  →  $($_.Exception.Message)" Red
            $failed++
        }
    }

    Write-Host ''
    Write-C ('=' * 50) Cyan
    Write-Ok "成功删除 $success 个文件"
    if ($failed -gt 0) {
        Write-Err "失败 $failed 个文件（可能被占用，请关闭游戏后再试）"
    }
    Write-C ('=' * 50) Cyan

    if ($deleted.Count -gt 0) {
        try {
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('===== ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' =====')
            foreach ($d in $deleted) { [void]$sb.AppendLine($d) }
            [IO.File]::AppendAllText($script:LogFile, $sb.ToString(), $script:Utf8NoBom)
            Write-Info "删除记录已保存到 $(Split-Path -Leaf $script:LogFile)"
        } catch {
            Write-Warn "删除记录保存失败：$($_.Exception.Message)"
        }
    }
}

# ============================================================
#  菜单与主流程
# ============================================================
function Show-Menu {
    param([string]$GtaPath)

    Clear-Host
    Write-C ('=' * 60) Cyan
    Write-C '       Grand Theft Auto V Enhanced 文件扫描器' Cyan
    Write-C ('=' * 60) Cyan

    Write-C '当前路径: ' White -NoNewline
    if ($GtaPath) { Write-C $GtaPath Green } else { Write-C '未设置' Red }

    Write-C ('-' * 60) DarkGray
    Write-C '  1. ' Yellow -NoNewline
    Write-C '★开始扫描目录文件★' White
    Write-C '  2. ' Yellow -NoNewline
    Write-C '重新设定 GTA 路径' White
    Write-C '  3. ' Yellow -NoNewline
    Write-C '打开纯净目录清单' White
    Write-C '  4. ' Yellow -NoNewline
    Write-C '打开当前 GTA 目录' White
    Write-C '  5. ' Yellow -NoNewline
    Write-C '更新此脚本' White
    Write-C '  0. ' Yellow -NoNewline
    Write-C '退出' White
    Write-C ('-' * 60) DarkGray
    Write-C '请按数字键选择：' Cyan -NoNewline
}

function Open-PathItem {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Err "文件/目录不存在: $Path"
        return
    }
    try {
        Start-Process -FilePath $Path
        Write-Ok "已打开 $Path"
    } catch {
        Write-Err "无法打开: $($_.Exception.Message)"
    }
}

function Invoke-Scan {
    param([string]$GtaPath)

    Clear-Host
    Write-Info '正在解析官方干净列表...'
    $official = Get-OfficialList $script:DirListFile
    if ($official.Count -eq 0) {
        Write-Err '官方列表解析失败或为空，请检查 GTA-Directory.txt 格式。'
        Write-C '按任意键返回菜单...' DarkGray
        [void](Read-Key)
        return
    }

    Write-Ok "官方列表解析完成，共 $($official.Count) 个文件。"
    Write-C "正在扫描实际目录：$GtaPath" Cyan
    Write-C '（目录较大时可能需要几秒到几十秒，请耐心等待...）' DarkGray

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $scan = Get-RealFiles $GtaPath
    $sw.Stop()

    Write-Ok ("扫描完成，用时 {0:N1} 秒，共发现 {1} 个文件。" -f $sw.Elapsed.TotalSeconds, $scan.Files.Count)

    $result = Show-Report -Official $official -Real $scan.Files -Sizes $scan.Sizes -Root $GtaPath

    if ($result.Extra.Count -gt 0) {
        Invoke-DeleteFlow -Extra $result.Extra -HighRisk $result.HighRisk -Root $GtaPath
    }

    Write-Host ''
    Write-C '按任意键返回菜单...' DarkGray
    [void](Read-Key)
}

function Start-App {
    if (-not (Test-Path -LiteralPath $script:DirListFile -PathType Leaf)) {
        Write-C ('=' * 60) Red
        Write-Err 'GTA-Directory.txt 目录文件不存在！'
        Write-C '请把纯净文件清单放到脚本同级目录：' Yellow
        Write-C "  $($script:DirListFile)" White
        Write-C ('=' * 60) Red
        Write-C '按任意键退出...' DarkGray
        [void](Read-Key)
        return
    }

    $gtaPath = Get-SavedGtaPath
    if (-not $gtaPath) {
        Write-Info '首次运行或路径文件丢失，需要设置 GTA 路径'
        $gtaPath = Read-GtaPath
        if (-not $gtaPath) { return }
        Set-SavedGtaPath $gtaPath
    }

    while ($true) {
        Show-Menu $gtaPath
        $choice = (Read-Key).ToLower()

        switch ($choice) {
            '1' {
                Invoke-Scan $gtaPath
            }
            '2' {
                Clear-Host
                Write-Info '重新设定路径：'
                $newPath = Read-GtaPath
                if ($newPath) {
                    Set-SavedGtaPath $newPath
                    $gtaPath = $newPath
                }
                Write-C '按任意键返回菜单...' DarkGray
                [void](Read-Key)
            }
            '3' {
                Clear-Host
                Open-PathItem $script:DirListFile
                Write-C '按任意键返回菜单...' DarkGray
                [void](Read-Key)
            }
            '4' {
                Clear-Host
                if ($gtaPath -and (Test-Path -LiteralPath $gtaPath)) {
                    Open-PathItem $gtaPath
                } else {
                    Write-Err '路径无效'
                }
                Write-C '按任意键返回菜单...' DarkGray
                [void](Read-Key)
            }
            '5' {
                Clear-Host
                try {
                    Start-Process $script:UpdateUrl
                    Write-Ok '已在浏览器打开更新页面。'
                } catch {
                    Write-Err "无法打开浏览器：$($_.Exception.Message)"
                }
                Write-C '按任意键返回菜单...' DarkGray
                [void](Read-Key)
            }
            { $_ -in @('0', 'q') } {
                Clear-Host
                Write-C '再见！祝你游戏愉快，远离封禁。' Green
                return
            }
            default {
                Write-Warn '无效选项，请重新选择。'
                Start-Sleep -Milliseconds 800
            }
        }
    }
}

# ============================================================
#  入口
# ============================================================
try {
    Start-App
} catch {
    Write-Host ''
    Write-Err "致命错误: $($_.Exception.Message)"
    Write-C $_.ScriptStackTrace DarkGray
    Write-C '按任意键退出...' DarkGray
    [void](Read-Key)
}
