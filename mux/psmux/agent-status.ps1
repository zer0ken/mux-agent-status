# mux-agent-status 의 psmux 진입점. psmux.conf 에서 이 파일을 부른다.
#
#   run-shell "~/mux-agent-status/mux/psmux/agent-status.ps1"
#
# psmux 는 PowerShell 로 명령을 돌린다(공식 문서의 run-shell 예시가 전부
# .ps1 스크립트를 쓴다). 티커 자체는 bash 스크립트(agent-status.sh, Git
# Bash 로 돈다)라서, 이 진입점은 그 스크립트를 psmux 와 분리된 새 프로세스로
# 띄우기만 한다.
#
# 티커는 psmux 의 감시 밖에서 띄운다. run-shell 이 지켜보는 채로 띄우면
# psmux 가 그 프로세스를 계속 지켜보다가 종료 시그널을 받고 죽을 때 오류
# 창을 띄운다. 티커는 서버가 살아 있는 내내 도는 프로세스라 언젠가는
# 반드시 그렇게 끝난다.
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $dir "agent-status.sh"
$bash = "C:\Program Files\Git\bin\bash.exe"
if (-not (Test-Path $bash)) {
    $bash = (Get-Command bash -ErrorAction SilentlyContinue).Source
}
if ($bash) {
    Start-Process -FilePath $bash -ArgumentList $script -WindowStyle Hidden
}
