/**
 * pi 세션의 상태를 파일 하나에 쓴다. tmux-agent-status 티커가 그 파일을 읽어
 * tmux 상태바에 표시한다.
 *
 * pi 는 실행 중인 세션의 목록도, 상태 파일도 내보내지 않는다. Claude Code 의
 * ~/.claude/sessions/<pid>.json 에 해당하는 것이 없어서 이 확장이 대신 쓴다.
 *
 * 파일: $TMPDIR/tmux-agent-status-<uid>/pi-<pane>
 * 내용: "<상태> <pid>"
 *
 * 상태는 티커가 쓰는 어휘를 그대로 쓴다.
 *   idle     사용자 입력을 기다린다
 *   busy     돌고 있다
 *   waiting  대화형 툴이 답을 기다린다
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { writeFileSync, unlinkSync, existsSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";

type State = "idle" | "busy" | "waiting";

// 사용자가 답해야 끝나는 툴. 도는 동안 세션은 waiting 이다.
const INTERACTIVE_TOOLS = new Set(["ask_user_question"]);

export default function (pi: ExtensionAPI) {
  const pane = process.env.TMUX_PANE;
  if (!pane) return;   // tmux 밖에서는 표시할 곳이 없다

  const uid = typeof process.getuid === "function" ? process.getuid() : 0;
  const dir = `${process.env.TMPDIR ?? tmpdir()}/tmux-agent-status-${uid}`;
  const file = `${dir}/pi-${pane.replace("%", "")}`;

  let state: State = "idle";
  let interactive = 0;

  // 상태 파일을 못 써도 pi 는 그대로 돈다. 배지만 안 나온다.
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
