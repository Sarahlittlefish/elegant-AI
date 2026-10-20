@echo off
setlocal
title Kai local model test
set "KAI_BAT=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:KAI_BAT,[Text.Encoding]::UTF8); $m='#'+'==PS-START=='; $i=$s.IndexOf($m); if($i -lt 0){Write-Host 'script damaged, please download again'; exit 1}; $t=Join-Path $env:TEMP 'kai-local-test.ps1'; [IO.File]::WriteAllText($t,$s.Substring($i),(New-Object Text.UTF8Encoding $true)); & $t"
echo.
pause
exit /b
#==PS-START==
# Kai 本地模型一键测速
# 做的事：找个地方放文件 -> 下载 llama.cpp（Vulkan 显卡版）-> 从魔搭下载 Qwen3 模型
#        -> 开本地服务（关掉思考模式）-> 测速 -> 打开聊天网页
# 这个脚本里没有任何密钥，可以放心公开。

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Kai 本地模型（关掉这个窗口 = 停止模型）' } catch {}

# ---------------- 固定配置（都核实过） ----------------
$LlamaTag  = 'b11756'
$LlamaZip  = "llama-$LlamaTag-bin-win-vulkan-x64.zip"
$LlamaSize = 36751610
$LlamaSha  = '75ce69fdda503c3d6d3b3401f61369bd072194746ec65fbbc5fd7e749edd2914'
$LlamaUrl  = "https://github.com/ggml-org/llama.cpp/releases/download/$LlamaTag/$LlamaZip"
# GitHub 在国内经常很慢，先试国内能用的镜像，最后才直连 GitHub
$GhMirrors = @('https://gh-proxy.com/', 'https://ghfast.top/', 'https://ghproxy.net/', 'https://gh.llkk.cc/', '')

$Models = [ordered]@{
  '4B' = @{ Name = 'Qwen3-4B'; File = 'Qwen3-4B-Q4_K_M.gguf'; Size = [int64]2497280256
            Sha  = '7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5'
            Url  = 'https://modelscope.cn/models/Qwen/Qwen3-4B-GGUF/resolve/master/Qwen3-4B-Q4_K_M.gguf'
            Alias = 'qwen3-4b' }
  '8B' = @{ Name = 'Qwen3-8B'; File = 'Qwen3-8B-Q4_K_M.gguf'; Size = [int64]5027783488
            Sha  = 'd98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785'
            Url  = 'https://modelscope.cn/models/Qwen/Qwen3-8B-GGUF/resolve/master/Qwen3-8B-Q4_K_M.gguf'
            Alias = 'qwen3-8b' }
}
$Port = 8080
$Ctx  = 4096
$ConfigDir  = Join-Path $env:LOCALAPPDATA 'KaiLocal'
$ConfigFile = Join-Path $ConfigDir 'location.txt'
$script:Proc = $null

# ---------------- 小工具 ----------------
function Say($t, $c = 'White') { Write-Host $t -ForegroundColor $c }
function Step($t) { Write-Host ''; Write-Host "==== $t ====" -ForegroundColor Cyan }
function Good($t) { Write-Host "  [好] $t" -ForegroundColor Green }
function Warn($t) { Write-Host "  [注意] $t" -ForegroundColor Yellow }
function Bad($t)  { Write-Host "  [出错] $t" -ForegroundColor Red }
function Fail($t) {
  Bad $t
  Write-Host ''
  Say '脚本先停在这里。照上面说的处理好，再双击一次就行，已经下好的东西不会重新下。' 'Yellow'
  Say '还是不行的话，把这个窗口拍照发给 Charlie。' 'Yellow'
  Stop-Llama
  exit 1
}
function GB($b) { if ($b -lt 1GB) { return ('{0:N0} MB' -f ($b / 1MB)) }; return ('{0:N1} GB' -f ($b / 1GB)) }

# 倒计时选择：不按键就用默认值
function Read-Choice([string[]]$valid, [string]$default, [int]$seconds) {
  try { while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) } } catch { return $default }
  $end = (Get-Date).AddSeconds($seconds)
  $last = -1
  while ((Get-Date) -lt $end) {
    $left = [int][Math]::Ceiling(($end - (Get-Date)).TotalSeconds)
    if ($left -ne $last) { Write-Host -NoNewline ("`r  按数字键选择；{0} 秒后自动选 {1}   " -f $left, $default); $last = $left }
    $avail = $false
    try { $avail = [Console]::KeyAvailable } catch { Write-Host ''; return $default }
    if ($avail) {
      $k = [Console]::ReadKey($true)
      $c = [string]$k.KeyChar
      if ($k.Key -eq 'Enter') { Write-Host ''; return $default }
      if ($valid -contains $c) { Write-Host ''; Say "  你选了 $c" 'Gray'; return $c }
    }
    Start-Sleep -Milliseconds 100
  }
  Write-Host ''
  return $default
}

# 读取系统代理（开了 VPN 的「系统代理」模式时，用它去连 GitHub）
function Get-SysProxy {
  try {
    $k = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
    if ($k.ProxyEnable -eq 1 -and $k.ProxyServer) {
      $p = [string]$k.ProxyServer
      if ($p -match '=') {
        $found = $null
        foreach ($part in $p.Split(';')) {
          if ($part -match '^\s*https=(.+)$') { $found = $Matches[1]; break }
          if ($part -match '^\s*http=(.+)$') { $found = $Matches[1] }
        }
        if (-not $found) { return $null }
        $p = $found
      }
      if ($p -notmatch '://') { $p = 'http://' + $p }
      return $p
    }
  } catch {}
  return $null
}

$CurlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue

# 保险：把模型服务和这个窗口绑在一起，窗口一关，服务一定跟着停
$script:JobOk = $false
try {
  Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class KaiJob {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr attr, string name);
  [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint len);
  [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr proc);
  [StructLayout(LayoutKind.Sequential)] struct BASIC { public long a; public long b; public uint LimitFlags; public UIntPtr c; public UIntPtr d; public uint e; public UIntPtr f; public uint g; public uint h; }
  [StructLayout(LayoutKind.Sequential)] struct IOC { public ulong a, b, c, d, e, f; }
  [StructLayout(LayoutKind.Sequential)] struct EXT { public BASIC Basic; public IOC Io; public UIntPtr p1, p2, p3, p4; }
  static IntPtr job = IntPtr.Zero;
  public static bool Add(IntPtr hProcess) {
    if (job == IntPtr.Zero) {
      job = CreateJobObject(IntPtr.Zero, null);
      if (job == IntPtr.Zero) return false;
      EXT info = new EXT();
      info.Basic.LimitFlags = 0x2000; // KILL_ON_JOB_CLOSE
      int len = Marshal.SizeOf(typeof(EXT));
      IntPtr p = Marshal.AllocHGlobal(len);
      Marshal.StructureToPtr(info, p, false);
      if (!SetInformationJobObject(job, 9, p, (uint)len)) return false;
    }
    return AssignProcessToJobObject(job, hProcess);
  }
}
'@
  $script:JobOk = $true
} catch {}

# 下载：支持断点续传，下完核对大小和 SHA256
function Get-FileChecked($urls, [string]$dest, [int64]$size, [string]$sha, [string]$proxy) {
  $ok = "$dest.ok"
  if ((Test-Path $dest) -and ((Get-Item $dest).Length -eq $size) -and (Test-Path $ok)) { return $true }
  foreach ($u in $urls) {
    if (-not ((Test-Path $dest) -and ((Get-Item $dest).Length -eq $size))) {
      $hostName = ([Uri]$u).Host
      $have = 0; if (Test-Path $dest) { $have = (Get-Item $dest).Length }
      if ($have -gt 0) { Say ("  从 {0} 接着下（已经有 {1}）……" -f $hostName, (GB $have)) 'Gray' }
      else { Say "  从 $hostName 下载……" 'Gray' }
      $code = 1
      if ($CurlCmd) {
        $a = @('-L', '-C', '-', '--fail', '--retry', '2', '--retry-delay', '3', '--connect-timeout', '20',
               '-y', '60', '-Y', '2048', '--ssl-no-revoke', '-o', $dest, $u)
        if ($proxy) { $a = @('-x', $proxy) + $a }
        & $CurlCmd.Source @a
        $code = $LASTEXITCODE
      } else {
        try { Invoke-WebRequest -Uri $u -OutFile $dest -UseBasicParsing; $code = 0 } catch { $code = 1 }
      }
    }
    if ((Test-Path $dest) -and ((Get-Item $dest).Length -eq $size)) {
      Say '  下完了，正在核对文件有没有损坏（大文件要等几十秒）……' 'Gray'
      $h = (Get-FileHash -Algorithm SHA256 -Path $dest).Hash.ToLower()
      if ($h -eq $sha) { Set-Content -Path $ok -Value $sha; return $true }
      Warn '文件核对不上，删掉重下。'
      Remove-Item $dest -Force -ErrorAction SilentlyContinue
    } elseif ((Test-Path $dest) -and ((Get-Item $dest).Length -gt $size)) {
      Remove-Item $dest -Force -ErrorAction SilentlyContinue
    } else {
      Warn "这次没下完（代码 $code），换个地址或再试一次。"
    }
  }
  return $false
}

# 和本地模型服务说话（不走代理，中文按 UTF-8）
function Invoke-Local([string]$method, [string]$path, [string]$json, [int]$timeoutSec) {
  try {
    $req = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:$Port$path")
    $req.Method = $method
    $req.Proxy = $null
    $req.Timeout = $timeoutSec * 1000
    $req.ReadWriteTimeout = $timeoutSec * 1000
    if ($json) {
      $bytes = [Text.Encoding]::UTF8.GetBytes($json)
      $req.ContentType = 'application/json; charset=utf-8'
      $req.ContentLength = $bytes.Length
      $st = $req.GetRequestStream(); $st.Write($bytes, 0, $bytes.Length); $st.Close()
    }
    $resp = $req.GetResponse()
    $code = [int]$resp.StatusCode
    $sr = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
    $body = $sr.ReadToEnd(); $sr.Close(); $resp.Close()
    return [pscustomobject]@{ Code = $code; Body = $body }
  } catch [System.Net.WebException] {
    $r = $_.Exception.Response
    if ($r) { $c = [int]$r.StatusCode; $r.Close(); return [pscustomobject]@{ Code = $c; Body = '' } }
    return $null
  } catch { return $null }
}

function Stop-Llama {
  if ($script:Proc -and -not $script:Proc.HasExited) {
    try { Stop-Process -Id $script:Proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    Start-Sleep -Seconds 1
  }
  $script:Proc = $null
}

# ---------------- 找存放位置 ----------------
function Get-DriveList {
  $res = @()
  $sys = $env:SystemDrive.Substring(0, 1).ToUpper()
  $vols = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object {
    $_.DriveLetter -and ($_.DriveType -eq 'Fixed' -or $_.DriveType -eq 'Removable') -and $_.SizeRemaining -gt 0 })
  foreach ($v in $vols) {
    $L = ([string]$v.DriveLetter).ToUpper()
    $fs = [string]$v.FileSystem
    if (@('NTFS', 'exFAT', 'ReFS', 'FAT32') -notcontains $fs) { continue }   # 比如 Mac 分区，Windows 写不进去
    $media = ''; $bus = ''
    try {
      $p = Get-Partition -DriveLetter $L -ErrorAction Stop | Select-Object -First 1
      $d = Get-Disk -Number $p.DiskNumber -ErrorAction Stop
      $bus = [string]$d.BusType
      $pd = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DeviceId -eq [string]$p.DiskNumber } | Select-Object -First 1
      if ($pd) { $media = [string]$pd.MediaType }
    } catch {}
    $isUsb = ($bus -eq 'USB') -or ($v.DriveType -eq 'Removable')
    if ($isUsb) {
      if ($media -eq 'SSD') { $kind = 'USB 固态盘'; $score = 70 } else { $kind = 'U盘/移动硬盘'; $score = 60 }
    } elseif ($media -eq 'SSD') { $kind = '固态硬盘 SSD'; $score = 100 }
    elseif ($media -eq 'HDD') { $kind = '机械硬盘'; $score = 30 }
    else { $kind = '硬盘（类型不明）'; $score = 40 }
    if ($L -eq $sys) { $kind += '，系统盘'; $score -= 25 }
    $res += [pscustomobject]@{ Letter = $L; Free = [int64]$v.SizeRemaining; FS = $fs; Kind = $kind; Score = $score; Usb = $isUsb }
  }
  return $res
}

function Get-ExistingBytes([string]$base, $keys) {
  $n = [int64]0
  foreach ($k in $keys) {
    $f = Join-Path $base ("models\" + $Models[$k].File)
    if (Test-Path $f) { $n += (Get-Item $f).Length }
  }
  return $n
}

function Select-Base($keys) {
  $need = [int64]500MB + 1GB
  foreach ($k in $keys) { $need += $Models[$k].Size }
  $bigFile = $keys -contains '8B'
  $all = @(Get-DriveList)
  $cands = @()
  foreach ($d in $all) {
    $base = "$($d.Letter):\KaiLocal"
    $want = $need - (Get-ExistingBytes $base $keys)
    if ($d.Free -lt $want) { continue }
    if ($bigFile -and $d.FS -eq 'FAT32') { continue }   # FAT32 放不下 4GB 以上的单个文件
    $cands += $d
  }
  $cands = @($cands | Sort-Object -Property @{Expression = 'Score'; Descending = $true}, @{Expression = 'Free'; Descending = $true})
  if ($cands.Count -eq 0) {
    Say '  现在的硬盘情况：' 'Gray'
    foreach ($d in $all) { Say ("   {0}:  {1}  还剩 {2}  ({3})" -f $d.Letter, $d.Kind, (GB $d.Free), $d.FS) 'Gray' }
    Fail ("没有哪个盘有 {0} 的空位。插上你的 1T U盘（要 NTFS 或 exFAT 格式），或者清出点空间，再双击一次。" -f (GB $need))
  }
  Say '  可以放的位置：'
  $i = 0
  foreach ($d in ($cands | Select-Object -First 9)) {
    $i++
    $tag = ''; if ($i -eq 1) { $tag = '  <- 推荐' }
    Say ("   {0}) {1}:\KaiLocal   {2}，还剩 {3}{4}" -f $i, $d.Letter, $d.Kind, (GB $d.Free), $tag)
  }
  $valid = @(); for ($j = 1; $j -le $i; $j++) { $valid += [string]$j }
  $pick = Read-Choice $valid '1' 20
  $chosen = $cands[[int]$pick - 1]
  if ($chosen.Usb) { Warn '放在U盘/移动硬盘上的话，以后每次用都要先插上它。' }
  if ($chosen.Kind -match '机械') { Warn '这是机械硬盘，下载和第一次加载会慢一点，但加载完以后聊天速度不受影响。' }
  return "$($chosen.Letter):\KaiLocal"
}

function Test-Writable([string]$dir) {
  try {
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    $t = Join-Path $dir 'write-test.tmp'
    Set-Content -Path $t -Value 'ok' -ErrorAction Stop
    Remove-Item $t -Force
    return $true
  } catch { return $false }
}

# ---------------- 开服务、测速 ----------------
function Get-FreePort {
  foreach ($p in 8080..8090) {
    $c = @(Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)
    if ($c.Count -eq 0) { return $p }
    $owner = $null
    try { $owner = Get-Process -Id $c[0].OwningProcess -ErrorAction Stop } catch {}
    if ($owner -and $owner.ProcessName -eq 'llama-server') {
      Say "  发现上次没关掉的模型服务，先把它关了。" 'Gray'
      Stop-Process -Id $owner.Id -Force -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 2
      return $p
    }
  }
  return 8091
}

function Start-Llama($m, [bool]$cpuOnly) {
  $modelPath = Join-Path $ModelDir $m.File
  $log = Join-Path $LogDir ("server-" + $m.Alias + ".log")
  $err = Join-Path $LogDir ("server-" + $m.Alias + ".err.log")
  Remove-Item $log, $err -Force -ErrorAction SilentlyContinue
  $argStr = "-m `"$modelPath`" --host 0.0.0.0 --port $Port -c $Ctx -np 1 -fitt 512 -rea off -a $($m.Alias) --temp 0.7 --top-p 0.8 --top-k 20 --min-p 0 -lv 4"
  if ($cpuOnly) { $argStr += ' -dev none -ngl 0' }
  elseif ($script:DevId) { $argStr += " -dev $($script:DevId)" }
  $script:Proc = Start-Process -FilePath $ServerExe -ArgumentList $argStr -WorkingDirectory $BinDir -NoNewWindow -PassThru `
    -RedirectStandardOutput $log -RedirectStandardError $err
  if ($script:JobOk -and $script:Proc) { try { [void][KaiJob]::Add($script:Proc.Handle) } catch {} }
  $script:LogFiles = @($log, $err)
}

function Read-Logs {
  $t = ''
  foreach ($f in $script:LogFiles) { if (Test-Path $f) { $t += (Get-Content $f -Raw -ErrorAction SilentlyContinue) + "`n" } }
  return $t
}

function Wait-Ready([int]$timeoutSec) {
  $t0 = Get-Date
  Write-Host -NoNewline '  加载中'
  while (((Get-Date) - $t0).TotalSeconds -lt $timeoutSec) {
    if ($script:Proc.HasExited) { Write-Host ''; return $false }
    $r = Invoke-Local 'GET' '/health' $null 5
    if ($r -and $r.Code -eq 200) { Write-Host ''; return $true }
    Write-Host -NoNewline '.'
    Start-Sleep -Seconds 2
  }
  Write-Host ''
  return $false
}

function New-Chat($alias, $messages, [int]$maxTokens) {
  $o = @{ model = $alias; messages = $messages; max_tokens = $maxTokens; temperature = 0.7; top_p = 0.8; top_k = 20
          cache_prompt = $false; stream = $false; chat_template_kwargs = @{ enable_thinking = $false } }
  return ($o | ConvertTo-Json -Depth 8 -Compress)
}

function Test-Speed($m) {
  # 热身一下
  [void](Invoke-Local 'POST' '/v1/chat/completions' (New-Chat $m.Alias @(@{ role = 'user'; content = '你好' }) 8) 600)

  # 1) 生成速度
  $msgs = @(@{ role = 'system'; content = '你是一个说话自然的朋友，用中文回答。' },
            @{ role = 'user'; content = '用三四句话说说上海的秋天是什么样的。' })
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $r = Invoke-Local 'POST' '/v1/chat/completions' (New-Chat $m.Alias $msgs 200) 900
  $sw.Stop()
  if (-not $r -or $r.Code -ne 200) { return $null }
  $j = $r.Body | ConvertFrom-Json
  $text = [string]$j.choices[0].message.content
  $think = $text -match '<think>'
  $text = [regex]::Replace($text, '(?s)<think>.*?</think>', '').Trim()
  $tgTok = [double]$j.timings.predicted_per_second
  $genSec = [double]$j.timings.predicted_ms / 1000
  $chars = ([regex]::Replace($text, '\s', '')).Length
  $charRate = 0; if ($genSec -gt 0) { $charRate = $chars / $genSec }

  # 2) 读提示的速度（Kai 的人设很长，这个决定第一句话要等多久）
  $para = '上海的秋天来得很慢，梧桐叶一点点变黄，早晚的风开始有点凉，街上的人换上了薄外套，学校门口的小吃摊冒着热气。'
  $long = ($para * 25) + "`n上面这段话里一共有几句话？只回答一个数字。"
  $r2 = Invoke-Local 'POST' '/v1/chat/completions' (New-Chat $m.Alias @(@{ role = 'user'; content = $long }) 8) 900
  $ppTok = 0; $ppN = 0
  if ($r2 -and $r2.Code -eq 200) {
    $j2 = $r2.Body | ConvertFrom-Json
    $ppTok = [double]$j2.timings.prompt_per_second
    $ppN = [int]$j2.timings.prompt_n
  }

  $logs = Read-Logs
  $layers = ''
  $mm = [regex]::Matches($logs, 'offloaded (\d+)/(\d+) layers to GPU')
  if ($mm.Count -gt 0) { $layers = $mm[$mm.Count - 1].Groups[1].Value + '/' + $mm[$mm.Count - 1].Groups[2].Value }

  return [pscustomobject]@{
    Name = $m.Name; Text = $text; Chars = $chars; Wall = $sw.Elapsed.TotalSeconds
    TgTok = $tgTok; CharRate = $charRate; PpTok = $ppTok; PpN = $ppN; Layers = $layers; Think = $think
  }
}

function Show-Result($res, [bool]$cpuOnly) {
  $lines = @()
  $lines += "==== $($res.Name) 测速结果 ===="
  if ($cpuOnly) { $lines += '运行方式：只用 CPU（显卡没用上）' }
  elseif ($res.Layers) {
    $p = $res.Layers.Split('/')
    if ($p[0] -eq $p[1]) { $lines += "显卡：$($res.Layers) 层，全部放在显卡上" }
    else { $lines += "显卡：$($res.Layers) 层在显卡上，其余的在 CPU 上（显存不够，所以会慢一些）" }
  }
  $lines += ('说话速度：每秒约 {0:N1} 个 token，约 {1:N0} 个汉字' -f $res.TgTok, $res.CharRate)
  $lines += ('这次回了 {0} 个字，从发出到收到一共 {1:N1} 秒' -f $res.Chars, $res.Wall)
  if ($res.PpTok -gt 0) {
    $lines += ('读提示速度：每秒约 {0:N0} 个 token（读 1000 个 token 约 {1:N1} 秒）' -f $res.PpTok, (1000 / $res.PpTok))
    $short = 0; if ($res.CharRate -gt 0) { $short = 30 / $res.CharRate + 60 / $res.PpTok }
    $first = 3000 / $res.PpTok
    $lines += ('估算：平时回一句 30 个字左右的话，大约 {0:N1} 秒' -f $short)
    $lines += ('估算：如果带上 3000 个 token 的人设，第一句要先多等约 {0:N0} 秒，之后会记住不用重读' -f $first)
  }
  if ($res.Think) { $lines += '（注意：回复里出现了思考内容，关思考模式可能没生效）' }
  $lines += "它这次说的：$($res.Text)"
  Write-Host ''
  foreach ($l in $lines) { Say "  $l" 'Green' }
  return $lines
}

function Get-LanIps {
  $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
    $_.IPAddress -match '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)' } | Select-Object -ExpandProperty IPAddress)
  return $ips
}

# ======================== 正式开始 ========================
try {
  Clear-Host
  Say '=============================================' 'Cyan'
  Say '   Kai 本地模型一键测速（Qwen3 + 显卡加速）' 'Cyan'
  Say '   全程自动；中途问你的问题，不按键也会自动选推荐的。' 'Cyan'
  Say '=============================================' 'Cyan'

  # ---- 上次放在哪 ----
  $Base = $null
  if (Test-Path $ConfigFile) {
    $prev = (Get-Content $ConfigFile -Raw).Trim()
    if ($prev -and (Test-Path $prev)) { $Base = $prev }
    elseif ($prev) {
      Warn "上次的文件放在 $prev，现在找不到（U盘没插？）。"
      Say '   1) 我去插上，插好后按 1     2) 重新选个地方（要重新下载）'
      $c = Read-Choice @('1', '2') '1' 60
      if ($c -eq '1' -and (Test-Path $prev)) { $Base = $prev }
      elseif ($c -eq '1') { Fail "还是找不到 $prev。插好U盘后再双击一次。" }
    }
  }
  if (-not $Base) {
    foreach ($d in @(Get-DriveList)) {
      $p = "$($d.Letter):\KaiLocal"
      if (Test-Path (Join-Path $p 'models')) { $Base = $p; break }
    }
  }

  # 上次没关掉的模型服务，先关掉
  Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path -match '\\KaiLocal\\' } |
    ForEach-Object { Say '  先关掉上次没关的模型服务。' 'Gray'; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }

  # ---- 要不要 8B ----
  Step '第 1 步：选模型'
  $have8 = $false
  if ($Base) { $f8 = Join-Path $Base ('models\' + $Models['8B'].File); $have8 = (Test-Path "$f8.ok") }
  Say '   1) 只测 Qwen3-4B（推荐先这样，下载约 2.5 GB）'
  Say '   2) 4B 和 8B 都测（8B 再多下约 5 GB，比 4B 聪明但慢不少）'
  $def = '1'; if ($have8) { $def = '2' }
  $choice = Read-Choice @('1', '2') $def 15
  $Keys = @('4B'); if ($choice -eq '2') { $Keys = @('8B', '4B') }   # 8B 先测，最后留 4B 开着聊天

  # ---- 放哪 ----
  Step '第 2 步：找地方放文件'
  if ($Base) {
    $drive = Get-DriveList | Where-Object { $_.Letter -eq $Base.Substring(0, 1).ToUpper() } | Select-Object -First 1
    $need = [int64]300MB; foreach ($k in $Keys) { $need += $Models[$k].Size }
    $need -= (Get-ExistingBytes $Base $Keys)
    if ($drive -and $drive.Free -lt $need) {
      Warn ("{0} 剩的空间不够这次要下载的 {1}，重新选个地方。" -f $Base, (GB $need))
      $Base = $null
    } else { Good "用上次的位置：$Base" }
  }
  while (-not $Base) {
    $Base = Select-Base $Keys
    if (-not (Test-Writable $Base)) { Warn "$Base 写不进去，换一个。"; $Base = $null }
  }
  if (-not (Test-Writable $Base)) { Fail "$Base 写不进去。换个盘：删掉 $ConfigFile 再双击一次。" }
  New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
  Set-Content -Path $ConfigFile -Value $Base
  $BinDir   = Join-Path $Base "bin\$LlamaTag"
  $ModelDir = Join-Path $Base 'models'
  $LogDir   = Join-Path $Base 'logs'
  $DlDir    = Join-Path $Base 'downloads'
  foreach ($d in @($BinDir, $ModelDir, $LogDir, $DlDir)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
  $ServerExe = Join-Path $BinDir 'llama-server.exe'
  Good "文件都放在 $Base"

  # ---- llama.cpp ----
  Step '第 3 步：准备 llama.cpp（显卡版，约 37 MB）'
  if (Test-Path $ServerExe) { Good '已经有了，跳过。' }
  else {
    $zip = Join-Path $DlDir $LlamaZip
    $manual = Join-Path (Join-Path $env:USERPROFILE 'Downloads') $LlamaZip
    if (-not (Test-Path $zip) -and (Test-Path $manual)) { Copy-Item $manual $zip }
    $urls = @(); foreach ($mi in $GhMirrors) { $urls += ($mi + $LlamaUrl) }
    $ok = Get-FileChecked $urls $zip $LlamaSize $LlamaSha $null
    if (-not $ok) {
      $px = Get-SysProxy
      if ($px) { Say "  镜像都不行，试试走你的 VPN 代理（$px）直连 GitHub……" 'Gray'; $ok = Get-FileChecked @($LlamaUrl) $zip $LlamaSize $LlamaSha $px }
    }
    if (-not $ok) {
      Fail ("llama.cpp 没下下来。办法：打开 VPN 再双击一次。`n         或者用浏览器下载这个文件，放进「下载」文件夹，再双击一次：`n         $LlamaUrl")
    }
    Say '  解压中……' 'Gray'
    try { Expand-Archive -Path $zip -DestinationPath $BinDir -Force -ErrorAction Stop } catch { Fail "解压失败：$($_.Exception.Message)。删掉 $zip 再双击一次。" }
    if (-not (Test-Path $ServerExe)) { Fail "解压后找不到 llama-server.exe。删掉 $BinDir 和 $zip 再双击一次。" }
    Good 'llama.cpp 准备好了。'
  }

  # ---- 模型 ----
  Step '第 4 步：从魔搭下载模型（国内源，不用开 VPN）'
  foreach ($k in $Keys) {
    $m = $Models[$k]
    $dest = Join-Path $ModelDir $m.File
    Say ("  {0}（{1}）" -f $m.Name, (GB $m.Size))
    $ok = Get-FileChecked @($m.Url, $m.Url, $m.Url) $dest $m.Size $m.Sha $null
    if (-not $ok) { Fail "$($m.Name) 没下完。先检查网络；如果开着 VPN，关掉 VPN 再双击一次（魔搭是国内的，开 VPN 反而可能慢）。下了一半的会接着下。" }
    Good "$($m.Name) 准备好了。"
  }

  # ---- 看显卡 ----
  Step '第 5 步：检查显卡'
  $devOut = (& $ServerExe --list-devices 2>&1 | ForEach-Object { "$_" }) -join "`n"
  $script:DevId = $null
  $devs = [regex]::Matches($devOut, '(?m)^\s*(Vulkan\d+):\s*(.+)$')
  if ($devs.Count -eq 0) {
    Warn '没找到能用的显卡（Vulkan），这次只能用 CPU 跑，会慢很多。'
    Warn '多半是显卡驱动太旧，测完以后可以把这个窗口拍给 Charlie，一起看怎么更新驱动。'
  } else {
    foreach ($d in $devs) { Say ("  找到：{0}  {1}" -f $d.Groups[1].Value, $d.Groups[2].Value) 'Gray' }
    $pickDev = $devs[0]
    foreach ($d in $devs) { if ($d.Groups[2].Value -match 'AMD|Radeon') { $pickDev = $d; break } }
    $script:DevId = $pickDev.Groups[1].Value
    Good "用这张显卡：$($pickDev.Groups[2].Value)"
  }
  $cpuOnly = ($devs.Count -eq 0)

  # ---- 测速 ----
  Step '第 6 步：开模型、测速'
  Say '  如果弹出「Windows 安全中心警报 / 防火墙」的窗口，点「允许访问」（这样以后 iPad 才能连上）。' 'Yellow'
  $Port = Get-FreePort
  $report = @()
  $report += "测速时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm')"
  $report += "llama.cpp 版本：$LlamaTag（Vulkan）  显卡：$($script:DevId)"
  $report += $devOut
  $lastModel = $null
  foreach ($k in $Keys) {
    $m = $Models[$k]
    Say ''
    Say "  正在加载 $($m.Name)……第一次可能要一两分钟" 'White'
    $useCpu = $cpuOnly
    Start-Llama $m $useCpu
    $ready = Wait-Ready 900
    if (-not $ready -and -not $useCpu) {
      $tail = (Read-Logs) -split "`n" | Where-Object { $_ -match 'error|fail|out of memory|ErrorOutOfDeviceMemory' } | Select-Object -Last 5
      foreach ($t in $tail) { Say "    $t" 'DarkGray' }
      Warn '用显卡没启动起来，改成只用 CPU 再试一次（会慢）。'
      Stop-Llama
      $useCpu = $true
      Start-Llama $m $useCpu
      $ready = Wait-Ready 900
    }
    if (-not $ready) {
      $tail = (Read-Logs) -split "`n" | Select-Object -Last 15
      foreach ($t in $tail) { Say "    $t" 'DarkGray' }
      Fail "$($m.Name) 启动失败。日志在 $LogDir，把这个窗口拍照发给 Charlie。"
    }
    Good "$($m.Name) 启动了，开始测速（大概几十秒）……"
    $res = Test-Speed $m
    if (-not $res) {
      $tail = (Read-Logs) -split "`n" | Select-Object -Last 15
      foreach ($t in $tail) { Say "    $t" 'DarkGray' }
      Fail "测速的时候出错了。日志在 $LogDir，把这个窗口拍照发给 Charlie。"
    }
    $report += ''
    $report += (Show-Result $res $useCpu)
    $lastModel = $m
    if ($k -ne $Keys[$Keys.Count - 1]) { Stop-Llama }
  }

  $resultFile = Join-Path $Base '测速结果.txt'
  $report | Out-File -FilePath $resultFile -Encoding UTF8

  # ---- 打开聊天网页 ----
  Step '好了！'
  $url = "http://127.0.0.1:$Port"
  Start-Process $url
  Say "  浏览器已经打开聊天网页：$url （没打开的话，自己在浏览器里输入这个地址）" 'Green'
  Say "  现在开着的是 $($lastModel.Name)，思考模式已关。" 'Green'
  Say "  测速结果也存在了：$resultFile" 'Green'
  $ips = @(Get-LanIps)
  if ($ips.Count -gt 0) {
    Say '  以后 iPad 连这台电脑用的地址（同一个 Wi-Fi 下，OpenAI 兼容接口）：' 'Gray'
    foreach ($ip in $ips) { Say "     http://${ip}:$Port/v1    模型名：$($lastModel.Alias)" 'Gray' }
  }
  Write-Host ''
  Say '  聊完了：在这个窗口按 Q 停止模型；直接点右上角 X 关掉窗口也会停止。' 'Yellow'
  Say '  下次想再用，双击同一个文件就行，不会重新下载。' 'Yellow'

  while ($true) {
    if ($script:Proc.HasExited) { Warn "模型服务自己停了。日志在 $LogDir"; break }
    $q = $false
    try { if ([Console]::KeyAvailable) { $kk = [Console]::ReadKey($true); if ($kk.Key -eq 'Q') { $q = $true } } } catch {}
    if ($q) { break }
    Start-Sleep -Milliseconds 300
  }
  Say '  正在停止模型……' 'Gray'
} finally {
  Stop-Llama
}
Say '  已停止。' 'Gray'
