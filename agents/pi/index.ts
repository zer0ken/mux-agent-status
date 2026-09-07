/**
 * pi 세션의 상태를 파일 하나에 쓴다. mux-agent-status 의 소비자가 그 파일을 읽어
 * 각자의 상태바에 표시한다.
 *
 * pi 는 실행 중인 세션의 목록도, 상태 파일도 내보내지 않는다. Claude Code 의
 * ~/.claude/sessions/<pid>.json 에 해당하는 것이 없어서 이 확장이 대신 쓴다.
 *
 * 파일: $TMPDIR/mux-agent-status[-<uid>]/<mux>/<세션>/pi-<pane>
 * 내용: "<상태> <pid>"
 *
 * mux 는 pi 프로세스 환경에서 판별한다. tmux 와 그 별칭(psmux 포함)은
 * TMUX_PANE 을, zellij 는 ZELLIJ_PANE_ID 를 심어 두므로 어느 것이 있는지로
 * 정하고, pane id 표기는 그 mux 가 원래 쓰는 그대로 남긴다(tmux 계열은 %
 * 를 뗀 숫자, zellij 는 ZELLIJ_PANE_ID 값 그대로).
 *
 * psmux 는 window_id 와 pane_id 를 세션마다 따로 채번해서, 서로 다른
 * 세션이 같은 pane 번호를 가질 수 있다. 세션 이름까지 넣어야 그 둘을
 * 가른다. tmux 는 pane_id 가 이미 서버 전체 고유라 세션 서브디렉터리가
 * 없어도 됐지만, 모든 mux 에 공통으로 두면 소비자 쪽 코드가 mux 마다
 * 갈리지 않는다.
 *
 * 상태는 소비자가 읽는 어휘를 그대로 쓴다.
 *   idle     사용자 입력을 기다린다
 *   busy     돌고 있다
 *   waiting  대화형 툴이 답을 기다린다
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { writeFileSync, unlinkSync, existsSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { execFileSync } from "node:child_process";

type State = "idle" | "busy" | "waiting";

// 사용자가 답해야 끝나는 툴. 도는 동안 세션은 waiting 이다.
const INTERACTIVE_TOOLS = new Set(["ask_user_question"]);

export default function (pi: ExtensionAPI) {
  const tmuxPane = process.env.TMUX_PANE;
  const zellijPaneId = process.env.ZELLIJ_PANE_ID;
  let mux: string;
  let pane: string;
  let session: string;
  if (tmuxPane) {
    mux = "tmux";
    pane = tmuxPane.replace("%", "");
    try {
      session = execFileSync("tmux", ["display-message", "-t", tmuxPane, "-p", "#S"], { encoding: "utf8" }).trim();
    } catch {
      return;   // 세션을 모르면 다른 세션의 pane 과 가를 수 없다
    }
  } else if (zellijPaneId && process.env.ZELLIJ_SESSION_NAME) {
    mux = "zellij";
    pane = zellijPaneId;
    session = process.env.ZELLIJ_SESSION_NAME;
  } else {
    return;   // 알려진 mux 밖에서는 표시할 곳이 없다
  }
  if (!session) return;

  // Windows 의 임시 디렉터리는 이미 사용자마다 갈라져 있어 경로에 uid 를 넣지
  // 않는다. POSIX 는 /tmp 를 공용으로 쓰므로 uid 로 갈라 둔다. 소비자가 bash 에서
  // 같은 판단을 하므로 양쪽 경로가 맞는다. Node 는 Windows 에서 process.getuid 를
  // 제공하지 않아, uid 를 그대로 쓰면 소비자가 읽는 경로와 어긋난다.
  const root = process.platform === "win32"
    ? "mux-agent-status"
    : `mux-agent-status-${process.getuid?.() ?? 0}`;
  const dir = `${process.env.TMPDIR ?? tmpdir()}/${root}/${mux}/${session}`;
  const file = `${dir}/pi-${pane}`;

  let state: State = "idle";
  let interactive = 0;

  // 상태 파일을 못 써도 pi 는 그대로 돈다. indicator 만 안 나온다.
  const write = () => {
    try {
      mkdirSync(dir, { recursive: true });
      writeFileSync(file, `${state} ${process.pid}\n`);
    } catch { /* 무시 */ }
  };
  const remove = () => {
    try { if (existsSync(file)) unlinkSync(file); } catch { /* 무시 */ }
  };
  const set = (s: State) => { if (s !== state) { state = s; write(); } };

  pi.on("session_start", () => { interactive = 0; state = "idle"; write(); });
  pi.on("agent_start", () => set("busy"));
  pi.on("agent_end", () => { interactive = 0; set("idle"); });

  pi.on("tool_call", (event) => {
    if (!INTERACTIVE_TOOLS.has(event.toolName)) return;
    interactive++;
    set("waiting");
  });
  pi.on("tool_execution_end", (event) => {
    if (!INTERACTIVE_TOOLS.has(event.toolName)) return;
    interactive = Math.max(0, interactive - 1);
    if (interactive === 0 && state === "waiting") set("busy");
  });

  pi.on("session_shutdown", () => remove());
  process.on("exit", () => remove());
}
