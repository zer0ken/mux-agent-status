# codex 세션의 상태를 파일 하나에 쓴다. Windows 에서 codex 가 부르는 훅이다.
# mux-agent-status 의 소비자가 그 파일을 읽어 각자의 상태바에 표시한다.
#
#   pwsh -NoProfile -File ~/mux-agent-status/agents/codex/agent-status.ps1 busy
#
# codex 는 훅 명령을 셸에 넘기지 않고 프로세스로 띄운다. Windows 는 `.sh` 로
# 끝나는 경로를 실행하지 못하고, `bash` 는 Git 의 bash 가 아니라
# %SystemRoot%\System32\bash.exe, 곧 WSL 런처를 가리키는 것이 보통이다. 그래서
# Windows 에서는 이 PowerShell 스크립트가 훅을 맡는다. agent-status.sh 는 POSIX
# 가 쓴다. 두 파일은 같은 경로에 같은 내용을 쓴다.
#
# 파일: $TMPDIR\mux-agent-status\<mux>\<세션>\codex-<pane>
# 내용: "<상태> <pid>"
#
# mux 는 codex 프로세스 환경에서 판별한다. tmux 와 그 별칭(psmux 포함)은
# TMUX_PANE 을, zellij 는 ZELLIJ_PANE_ID 를 심어 두므로 어느 것이 있는지로
# 정하고, pane id 표기는 그 mux 가 원래 쓰는 그대로 남긴다(tmux 계열은 %
# 를 뗀 숫자, zellij 는 ZELLIJ_PANE_ID 값 그대로).
#
# psmux 는 window_id 와 pane_id 를 세션마다 따로 채번해서, 서로 다른 세션이
# 같은 pane 번호를 가질 수 있다. 세션 이름까지 넣어야 그 둘을 가른다.
#
# 인자로 상태를 받는다. 어느 훅이 부르는지는 hooks.json 이 정한다.
#   busy    돌고 있다
#   idle    끝났다, 사용자 차례
#   remove  세션이 끝났다
param([string]$State)

$ErrorActionPreference = 'SilentlyContinue'

trap { exit 0 }   # 상태 파일을 못 써도 codex 는 그대로 돈다

$paneEnv = $env:TMUX_PANE
$zellijPane = $env:ZELLIJ_PANE_ID

if ($paneEnv) {
    $mux = 'tmux'
    $pane = $paneEnv -replace '^%', ''
    $session = (& tmux display-message -t $paneEnv -p '#S' 2>$null | Select-Object -First 1)
    if ($session) { $session = $session.Trim() }
} elseif ($zellijPane) {
    $mux = 'zellij'
    $pane = $zellijPane
    $session = $env:ZELLIJ_SESSION_NAME
} else {
    exit 0   # 알려진 mux 밖에서는 표시할 곳이 없다
}
if (-not $session) { exit 0 }   # 세션을 모르면 다른 세션의 pane 과 가를 수 없다

# Windows 의 임시 디렉터리는 이미 사용자마다 갈라져 있어 경로에 uid 를 넣지
# 않는다. POSIX 쪽 스크립트도 Windows 를 그렇게 다루므로 두 파일이 같은 곳을
# 가리킨다.
$root = if ($env:TMPDIR) { $env:TMPDIR } else { $env:TEMP }
$dir = Join-Path (Join-Path (Join-Path $root 'mux-agent-status') $mux) $session
$file = Join-Path $dir "codex-$pane"

# 조상을 훑어 codex 프로세스를 찾고 그 pid 를 적는다. codex 는 훅을 바로
# 띄우지 않고 중간 프로세스를 하나 더 두므로, 부모 pid 는 훅이 끝나면 함께
# 사라지는 껍데기다. 그것을 적으면 소비자가 죽은 pid 로 보고 살아 있는 세션의
# 상태 파일을 지운다. codex 의 pid 는 세션이 사는 내내 그대로이고 Windows
# 네이티브 pid 라서 소비자가 프로세스 목록으로 확인할 수 있다.
#
# codex 를 못 찾으면 0 을 적는다. 소비자는 0 을 보면 생존 검사를 건너뛰고
# 파일을 그대로 둔다. 짐작한 pid 를 적는 것보다 검사를 건너뛰는 것이 낫다.
$AGENT_PROCESS = 'codex'
$MAX_DEPTH = 8

$owner = 0
$cur = $PID
for ($depth = 0; $depth -lt $MAX_DEPTH; $depth++) {
    $info = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
    if (-not $info) { break }
    if ([System.IO.Path]::GetFileNameWithoutExtension($info.Name) -eq $AGENT_PROCESS) {
        $owner = $info.ProcessId
        break
    }
    if (-not $info.ParentProcessId -or $info.ParentProcessId -eq 0) { break }
    $cur = $info.ParentProcessId
}

switch ($State) {
    'remove' { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    { $_ -in 'busy', 'idle' } {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [System.IO.File]::WriteAllText($file, "$State $owner`n")
    }
}

exit 0
