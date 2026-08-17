# fe-harness — 설계 문서

> Claude Code 플러그인. AI 코딩 세션에서 **코드가 써지는 시점에** 품질을 통제한다.
>
> 저자: tinyhex · 작성 2026-08-17 · 최종 갱신 2026-08-17 · 기준 Claude Code v2.1.231
>
> 이 문서는 구현 브리프이자 의사결정 기록이다. 구현이 바뀌면 여기도 갱신한다.
> 다른 절을 가리킬 때는 `8장`처럼 장 번호로 쓴다.

---

## 1. 문제

Claude Code로 몇 주간 같은 저장소를 작업하면 코드가 난잡해진다.
실제로 겪은 증상 5개:

1. 한 턴의 작업 범위가 너무 커서 검토가 불가능해진다
2. 컴포넌트 하나가 너무 많은 일을 한다
3. 중복이 계속 생긴다
4. option flag props가 늘어난다
5. 재사용하지도 않을 컴포넌트를 파일 안에 인라인으로 만들어버린다

**다섯 개는 증상이고 원인은 하나다 — Claude는 "지금 열려 있는 이 파일 안에서"
문제를 풀려고 한다.**

새 파일을 만드는 건 비싸다. 위치를 정해야 하고, import를 고쳐야 하고,
기존 구조를 알아야 한다. 반면 현재 파일에 코드를 더 붙이는 건 공짜다. 그래서:

- 기존 코드를 안 찾아보니까 → **중복** (증상 3)
- 새 파일을 안 만드니까 → **인라인 컴포넌트** (증상 5)
- 분기를 새 컴포넌트로 안 빼니까 → **flag props** (증상 4)
- 다 한 파일에 넣으니까 → **컴포넌트 비대** (증상 2)
- 그걸 한 턴에 다 하니까 → **범위 폭발** (증상 1)

**처방의 핵심: 새 파일 만들기를 싸게, 기존 파일에 붙이기를 비싸게 만든다.**

---

## 2. 왜 규칙이 아니라 훅인가

공식 문서 두 대목:

> "Claude treats them as context, not enforced configuration.
> **To block an action regardless of what Claude decides, use a `PreToolUse` hook
> instead.**"

> "Claude's context window fills up fast, and performance degrades as it fills...
> Claude may start 'forgetting' earlier instructions."

`CLAUDE.md`에 규칙을 더 적을수록 컨텍스트만 차고 준수율은 떨어진다
(공식 권고 상한 200줄). 강제 가능한 것은 훅으로 내린다.

| 레이어 | 수단 | 결정성 | 컨텍스트 비용 |
| --- | --- | --- | --- |
| 항상 아는 사실 | `CLAUDE.md` | 권고 | 매 요청 전량 |
| 경로별 규칙 | `.claude/rules/*.md` + `paths:` | 권고 | 매칭 시에만 |
| 절차 / 레퍼런스 | Skills | 권고 | description만 상주 |
| **강제** | **Hooks** | **보장** | **0** |
| 격리 검증 | Subagents | 권고 | 별도 컨텍스트 |

훅은 권한 모드로도 우회되지 않는다:

> "`PreToolUse` hooks fire before any permission-mode check... A hook that returns
> `permissionDecision: "deny"` blocks the tool **even in `bypassPermissions` mode**."

---

## 3. 4레이어 구조

```
[1] 쓰기 전에 알려주기    .claude/rules/ + paths, SessionStart(compact) 훅
[2] 쓰기 직전에 반려하기   PreToolUse × tool_input 내용 검사      ★ 핵심
[3] 애초에 작게 쓰게 하기   분량 게이트 (비대칭 임계값)             ★ 최대 지렛대
[4] 사후 리뷰            리뷰 시점 도구 + fe-harness refactor-pass
```

레이어 2가 성립하는 이유: `PreToolUse` 훅의 `tool_input`에 **쓰려는 내용 전문**이
온다. `Write`면 `.tool_input.content`, `Edit`면 `.tool_input.new_string`.
여기서 exit 2로 거부하면 파일에 안 들어가고 Claude가 다시 쓴다.

> ⚠️ **미검증** — `content`가 잘리지 않고 전문으로 오는지는 아직 실측 안 됨.
> 8장 참조.

> ⚠️ **`Edit`은 파일 전문이 오지 않는다.** `new_string`은 교체 조각이다.
>
> 분량 게이트(P0-2)는 "이번 턴에 얼마나 붙이는가"를 재므로 조각 기준이 맞다.
> 그러나 컴포넌트 카운트(P0-3)는 **파일 전체 기준**이어야 한다 — 두 번째
> 컴포넌트를 `Edit`으로 끼워 넣으면 `new_string`엔 1개만 보이고 파일엔 2개가 된다.
>
> 이건 위 미검증 항목의 답과 무관하게 발생한다. 대응은 4장 P0-3 참조.

---

## 4. 빌드 목록

우선순위만 매긴다. **기간은 적지 않는다** — 앞 단계의 결과가 뒤 단계의 설계를
바꾸기 때문에(8장 ①이 대표적인 예다) 주차로 묶어봐야 첫 실측에서 무의미해진다.
순서는 9장, 써보고 바꾼 것은 11장에 남긴다.

### P0 — 이게 없으면 나머지가 의미 없다

- **1 · 포맷** — `PostToolUse` · diff 가독성
  편집된 **파일 1개만** 포맷
- **2 · 분량 게이트** — `PreToolUse` · 증상 ① 범위 폭발
  임계값 초과 시 **반려**
- **3 · 인라인 컴포넌트** — `PreToolUse` · 증상 ⑤
  한 파일에 컴포넌트가 2개 이상이면 **반려**

**P0-3은 P0-2와 같은 스크립트에 넣지 않는다.** 3장의 경고대로 판정 단위가 다르다.
P0-2는 조각(`new_string`) 기준, P0-3은 파일 전체 기준이다. `Edit`에서 P0-3을
하려면 기존 파일을 읽어 조각을 적용한 결과를 세거나, `PostToolUse` 경고로
내려가야 한다. 어느 쪽으로 갈지는 P0-2를 붙여보고 결정한다 (9장).

**포맷이 P0인 이유** — Claude가 `Write`로 만든 파일은 **에디터의 저장 이벤트를
안 거친다.** format-on-save가 걸려 있어도 적용되지 않는다. 포맷 안 된 코드가 섞인
diff는 사람이 검토할 수 없고, 그게 이 프로젝트의 목표를 정면으로 깬다.

**분량 게이트의 임계값은 비대칭이어야 한다:**

```
Write (새 파일)   : 넉넉하게 (제안 250줄)   ← 새 파일 만들기를 "싸게"
Edit  (기존 수정) : 빡빡하게 (제안 150줄)   ← 기존 파일에 붙이기를 "비싸게"
```

이게 1장의 처방을 그대로 구현한 것이다. **이 숫자는 근거 없는 첫 값이다** —
실제로 걸려보고 조정하며, 바꾼 이유는 11장에 남긴다.

### P1 — P0가 실제로 돌아간 뒤

- **4 · 품질 게이트** — `Stop` · 안전망
  tsc + 변경분 테스트 통과 전 종료 차단
- **5 · flag props** — `PostToolUse` · 증상 ④
  **경고만.** boolean prop 2개 이상
- **6 · 린트 피드백** — `PostToolUse` · 피드백 루프
  `--fix` 후 남은 것만 stderr
- **7 · 컴팩션 재주입** — `SessionStart(compact)` · 규칙 희석
  stdout이 컨텍스트로 가는 3개 이벤트 중 하나

**린트를 넣는 이유는 중복 검사가 아니다.** Claude는 자기가 만든 lint 에러를
모른다 — IDE 인라인 표시는 사람만 보고, CI는 몇 분 뒤다. `PostToolUse` exit 2의
stderr는 **그 턴 안에서** Claude에게 간다. 피드백 루프를 분 단위에서 초 단위로
줄이는 게 목적이다.

단, ESLint 설정이 없는 프로젝트에는 도움이 안 된다. 훅은 린터를 대체하지 못하고
호출할 뿐이다.

### P2 — 훅이 다 자리잡은 뒤

- **8 · 토큰 하드코딩 경고** — **경고만.**
  hex 리터럴 + Tailwind arbitrary value 두 패턴.
  Tailwind 기본 팔레트 이탈(`bg-blue-500`)은 못 잡는다 → README 「알려진 한계」에 명시
- **9 · `.claude/rules/` + grep 강제** — 증상 ③ 중복. 플러그인이 아니라 프로젝트 쪽.
  "새 유틸을 만들기 전 반드시 Grep으로 기존 것을 찾고 결과를 보여줄 것"
- **10 · `entropy-auditor` 서브에이전트** — 누적 구조 부채 감사.
  리뷰 시점 도구와 축이 다르다 (diff 축 vs 시간 축)
- **11 · `refactor-pass` 스킬** — 리뷰 지적을 실제 수정으로 옮기는 실행 도구
- **12 · `harness-doctor` 스킬** — 새 저장소 진단
- **13 · eval 자동화** — 최대 차별점

### 의도적으로 하지 않는 일

**fe-harness는 코드 품질 기준을 정의하지 않는다.** 훅은 셀 수 있는 것만 판단할 수
있고(7장), 응집도나 이름이 동작과 맞는지는 읽어야 아는 것이다.
선은 회사나 도구가 아니라 **강제 가능성**으로 긋는다.

```
셀 수 있는 것   → 스크립트 · 작성 시점 · 강제   ← fe-harness
                  줄 수, 컴포넌트 개수, boolean prop 개수, hex 리터럴

읽어야 아는 것  → 모델 · 리뷰 시점 · 권고      ← toss/frontend-fundamentals 등
                  응집도, 결합도, 예측 가능성, 이름의 적절성
```

이 선으로 그으면 P1-5(flag props)와 P2-8(토큰 하드코딩)이 모순 없이 왼쪽에
들어온다 — 품질 의견이긴 하지만 **셀 수 있으니까** 훅이 할 수 있다.
반대로 셀 수 없는 것은 아무리 중요해도 이 저장소에 넣지 않는다.

리뷰 시점 도구와는 **같이 설치해서 쓴다.** 스킬 본문은 한 번 호출되면 세션 내내
컨텍스트에 남으므로, 같은 층위의 규칙을 두 벌 얹으면 비용이 두 배가 되고
충돌할 때 Claude가 임의로 하나를 고른다.

**그 외에 안 만드는 것**

- 자동 호출 스킬 — P0~P2 전부 `disable-model-invocation: true`
- 포맷 이외의 스타일 규칙 — 린터 영역

**toss/frontend-fundamentals에서 빌려올 것 3개** — P2-13 eval 만들 때 쓴다.

- `agents/reviewer.md`의 **스킬 로딩 강제 프롬프팅**
  "STOP - Read This First" + 변명별 반박 표
- `eval/graders/grader.md`의 **`Must NOT Suggest`** 절
  과잉 엔지니어링 제안을 감점 처리
- eval의 **baseline vs with-skill 비교** 설계

---

## 5. 검증 완료된 탐지 로직

`hooks/scripts/lib-detect.sh`. **모두 stdin으로 코드 본문을 받는다** — 임시파일
없음(BSD `mktemp` 호환 문제 회피).

```bash
#!/usr/bin/env bash
# fe-harness 탐지 primitive. 정규식 수정 시 test.sh 를 반드시 돌릴 것.

# 컴포넌트 선언 개수
fh_count_components() {
  local body decl assign
  body=$(cat)
  decl=$(printf '%s\n' "$body" | grep -cE '^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?function[[:space:]]+[A-Z][A-Za-z0-9_]*[[:space:]]*[(<]')
  assign=$(printf '%s\n' "$body" \
    | grep -E '^[[:space:]]*(export[[:space:]]+)?const[[:space:]]+[A-Z][A-Za-z0-9_]*[[:space:]]*(:[^=]*)?=[[:space:]]*(memo\b|forwardRef\b|function\b|\(|async[[:space:]]*\(|[a-z_$][A-Za-z0-9_$]*[[:space:]]*=>)' \
    | grep -cvE '=[[:space:]]*styled')
  echo $(( decl + assign ))
}

# Props 타입 내 boolean prop 이 THRESH 이상인 것 보고
fh_flag_props() {
  awk -v THRESH="${1:-2}" '
  function nm(s){ sub(/^[[:space:]]*(export[[:space:]]+)?(interface|type)[[:space:]]+/,"",s); sub(/[[:space:]]*[={].*$/,"",s); return s }
  /^[[:space:]]*(export[[:space:]]+)?(interface|type)[[:space:]]+[A-Za-z0-9_]*Props/ { inblk=1; name=nm($0); cnt=0; next }
  inblk && /^[[:space:]]*}/ { if (cnt>=THRESH) printf "%s (boolean prop %d개)\n", name, cnt; inblk=0; next }
  inblk && /^[[:space:]]*[A-Za-z0-9_]+\??[[:space:]]*:[[:space:]]*boolean[[:space:]]*;?[[:space:]]*$/ { cnt++ }
  '
}
```

### 검증 결과 (fixtures 실측)

**음성 11종 — 오탐 0**

`styled.div` / `styled(X)` / `styled.button({})` / `MAX_ITEMS` / `ROUTES` 객체 /
`new ApiClient()` / `z.object()` / 소문자 함수 / `type` / `interface`

**양성 9종 — 미탐 0**

`function Foo()` / `export function` / `export default function` /
`const F = () =>` / `React.FC` / `memo(...)` / `forwardRef<T>(...)` /
`props =>` / `async () =>`

**flag props — 콜백 제외 정확**

`onToggle: (next: boolean) => void`, `render?: (open: boolean) => ReactNode`

### 실측 환경

2026-08-17, macOS 24.6.0 arm64 — bash 3.2.57 · BSD grep · awk 20200816 · jq 1.7.1.

bash 3.2라서 연관배열(`declare -A`)과 `${var^^}` 같은 bash 4 문법은 쓸 수 없다.
훅 스크립트 전부 여기에 맞춘다.

### 발견한 한계 — flag props는 멤버 구분자가 `;`일 때만 잡는다

`type BannerProps = { a: boolean, b: boolean }`처럼 콤마로 구분하면 미탐이다.
Prettier 기본이 `;`라 실사용 영향은 작고, P1-5는 어차피 경고 전용이라
**미탐은 오탐보다 싼 실패**다. 고치지 않고 README 「알려진 한계」로 넘긴다.

### 개발 중 잡은 버그 2개 (블로그 소재)

- `const [A-Z]`만으로 세면 `styled.div`, `MAX_ITEMS`, `new ApiClient()`가 전부
  컴포넌트로 잡힌다 → 정상 파일이 1개가 아니라 5개로 나왔다.
  **우변이 함수처럼 생겼을 때만** 세도록 수정.
- `forwardRef\(`로 쓰면 제네릭이 낀 `forwardRef<HTMLDivElement>(`를 놓친다
  → `forwardRef\b`.

### 회귀 테스트

`fixtures/` 8개 파일 + `test.sh`. **정규식을 고칠 때마다 돌린다.**
새 오탐/미탐을 발견하면 그 코드를 fixtures에 추가하고 기대값을 박는다.
이게 나중에 만들 eval 하니스의 축소판이다.

현재 상태 `pass=12 fail=0` — 컴포넌트 카운트 6 · flag props 2 · 포맷 훅 4.

---

## 6. 폴더 구조

```
fe-harness/
├── .claude-plugin/
│   ├── plugin.json          ← 이 폴더엔 매니페스트만
│   └── marketplace.json
├── hooks/
│   ├── hooks.json
│   └── scripts/
│       ├── lib-detect.sh    ← 5장, 검증 완료
│       ├── lib-config.sh    ← 설정 3단 폴백
│       ├── format.sh        ← P0-1
│       ├── guard-write.sh   ← P0-2, P0-3 (PreToolUse)
│       └── warn-write.sh    ← P1-5, P1-6 (PostToolUse)
├── fixtures/                ← 탐지 로직 테스트 데이터
├── test.sh
├── .fe-harness.example.json
├── docs/DESIGN.md           ← 이 문서
└── README.md
```

**흔한 실수** — `hooks/`, `skills/`, `agents/`를 `.claude-plugin/` **안에** 넣는 것.
매니페스트만 그 안에 들어간다.

### hooks.json

최종 형태:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "^(Write|Edit)$",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/guard-write.sh",
            "args": [],
            "timeout": 30,
            "statusMessage": "작성 규모 확인"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "^(Write|Edit)$",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/format.sh",
            "args": [],
            "timeout": 60,
            "statusMessage": "포맷"
          },
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/warn-write.sh",
            "args": [],
            "timeout": 60,
            "statusMessage": "구조 신호 확인"
          }
        ]
      }
    ]
  }
}
```

**`"args": []`** — 셸을 안 거치고 직접 실행. 쿼팅 사고가 사라진다.

**matcher를 `^(...)$`로 감싼다.** 7장의 경고대로 matcher는 unanchored라
`Write|Edit`는 `NotebookEdit`에도 걸린다.

**존재하지 않는 스크립트는 등록하지 않는다.** 경로가 틀리면 게이트가 조용히
꺼지고, 그게 이 프로젝트에서 제일 잡기 어려운 실패다(7장). 현재 `hooks.json`에는
`format.sh`만 올라가 있고, 나머지는 만들면서 하나씩 추가한다.

### 설정 파일 — 3단 폴백

하네스는 특정 프로젝트를 알면 안 된다. `pnpm typecheck`를 하드코딩하면
다른 저장소에서 조용히 죽는다.

```
1) 프로젝트 루트 .fe-harness.json 이 있으면  → 무조건 신뢰
2) 없으면 추론 (lockfile / package.json scripts / 설정파일 존재)
3) 추론도 실패하면                          → 조용히 통과 (빈 문자열)
```

**3번이 핵심이다.** 하네스가 확신 없이 뭔가 실행해서 개발을 막는 것보다
아무것도 안 하는 게 낫다. `jq`가 없을 때 전체를 no-op으로 만드는 것도 같은 원칙.

```json
{
  "maxNewFileLines": 250,
  "maxEditLines": 150,
  "maxComponentsPerFile": 2,
  "maxBooleanProps": 2,
  "exclude": ["**/*.stories.tsx", "**/*.test.tsx", "**/*.spec.tsx", "src/gen/**"],
  "format": "",
  "lint": "",
  "typecheck": "",
  "test": "",
  "disable": { "guard": false, "format": false, "warn": false, "gate": false }
}
```

**`disable`을 반드시 넣는다.** 도구가 방해될 때 끌 방법이 없으면 사용자는
플러그인을 삭제한다.

---

## 7. 훅 작성 시 반드시 지킬 것

문서 원문으로 확인한, **틀리면 몇 시간 날리는** 것들.

**exit 1은 차단하지 않는다.** 정책 훅은 반드시 `exit 2`.

> "exit code 2 is the only exit code that blocks... Claude Code treats exit code 1
> as a **non-blocking error and proceeds**."

**`set -e` 금지.** 실패 시 exit 1이 나가서 차단이 안 된다. `set -uo pipefail`만.

**필드명.** `PostToolUse`의 결과는 `tool_response`. `tool_output` 아님.

**stdout이 컨텍스트로 가는 이벤트는 3개뿐.** `UserPromptSubmit`,
`UserPromptExpansion`, `SessionStart`. 그래서 컴팩션 재주입이 `SessionStart`다.

**`PostToolUse`의 exit 2**는 차단이 아니라 **stderr를 Claude에게 보여주기**다.
경고 훅은 이걸 쓴다.

**`Stop` 훅**은 `stop_hook_active` 파싱이 필수다(무한 루프).
**연속 8회 차단하면 무시**된다.

**matcher는 대소문자를 구분하고 unanchored다.** `Edit.*`는 `NotebookEdit`에도
걸린다 → `^Edit$`.

**`chmod +x`** 안 하면 조용히 실패한다.

**경로 오타가 나면 게이트가 조용히 꺼진다.** 첫 실행에서
`Failed with non-blocking status code`가 없는지 확인할 것.

**셸 프로필의 echo.** `.bashrc`의 무조건 `echo`가 stdout 앞에 붙으면 JSON이
통째로 무시된다. exit 0이면 화면에 아무것도 안 뜬다.

**stderr 메시지는 사람이 아니라 Claude가 읽는다.** "Blocked"만 쓰면 우회를
시도한다. **"대신 무엇을 하라"를 반드시 넣는다.**

**차단 vs 경고 판단.** 이 규칙을 정당하게 어겨야 하는 경우가 **주 1회 이상이면
경고**로 간다. 짜증나는 훅은 결국 꺼진다.

**성능.** `PostToolUse`는 매 편집마다 돈다. 저장소 전체를 돌면 결국 끄게 된다.
**편집된 파일 1개만.**

### 디버깅

```bash
claude --debug-file /tmp/claude.log   # 다른 터미널에서 tail -f
/debug                                # 세션 중 로깅 켜기
/hooks                                # 등록된 훅 + 어느 파일에서 왔는지
Ctrl+O                                # transcript — 훅 결과 확인
claude --safe-mode                    # 전부 끄고 대조
```

훅 직접 실행이 제일 빠르다:

```bash
echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/a.tsx","content":"x"}}' \
  | ./guard-write.sh; echo "exit=$?"
```

---

## 8. 미검증 항목

> **의사결정 (2026-08-17) — 검증을 별도 단계로 두지 않는다.**
>
> 초안은 착수 전에 버릴 훅을 settings에 심어 payload를 뜨는 계획이었다.
> 그런데 그건 `guard-write.sh`가 하는 일과 똑같다. **버릴 훅 대신 진짜 훅의 첫
> 버전을 _관찰 모드_(payload 로깅 후 `exit 0`)로 만들면 검증이 부산물로 나온다.**
> 플러그인 설치 때 어차피 세션 재시작이 필요하니 그 한 번에 합친다.
>
> 틀렸을 때 손해가 작다는 것이 근거다. content가 잘려 와도 버려지는 건
> `guard-write.sh`의 payload 파싱부뿐이고, `lib-detect.sh` · 설정 3단 폴백 ·
> 임계값 로직 · stderr 문구는 전부 살아남는다. 값싼 베팅이라 먼저 걸어본다.

### ① `PreToolUse`의 `tool_input.content`가 전문으로 오는가

**미검증.** P0-2가 여기 걸려 있다.

`guard-write.sh` 관찰 모드로 확인한다. `Write`의 `content`, `Edit`의 `new_string`
둘 다 본다.

```bash
jq '.tool_input | keys' <떠낸 payload>
jq -r '.tool_input.content // .tool_input.new_string' <떠낸 payload> | wc -l
```

잘려서 오면 `PostToolUse`에서 파일을 읽는 방식으로 바꿔야 하고, **그러면 반려가
아니라 경고만 가능해져 설계가 크게 달라진다.**

### ② macOS의 BSD `grep`/`awk`에서 탐지 로직이 동일하게 동작하는가

✅ **검증 완료** (2026-08-17). `./test.sh` 전부 통과.
환경과 발견한 한계는 5장에 기록.

### ③ 클래스 컴포넌트

`class Foo extends Component` — 현재 미지원. 쓰지 않으면 무시.

### ④ `Edit`의 `new_string`은 파일 전문이 아니다

✅ **확정된 사실.** 대응은 3장·4장 참조.
①의 답과 무관하게 P0-3의 판정 단위를 바꾼다.

---

## 9. 작업 순서

**만들면서 하나씩 검증한다.** 8장의 의사결정에 따라 별도 검증 단계는 없다.

- ~~**0** · 미검증 2개 확인~~ — 폐기. 각 훅에 흡수 (8장)
- ✅ **1** · 탐지 로직 + 회귀 테스트 — `test.sh` 통과
- ✅ **2** · 폴더 골격 + 매니페스트 + **포맷 훅**(P0-1)
  `claude plugin validate --strict` 통과 + 포맷 훅 케이스 통과
- **3** · 설치 + 세션 재시작
  `/hooks`에 뜨고, 첫 실행에 `Failed with non-blocking status code` 없음
- **4** · `guard-write.sh` **관찰 모드**
  payload 로그에 `content`/`new_string` 전문 존재 → 8장 ① 판정
- **5** · **분량 게이트**(P0-2) 반려 로직 부착
  일부러 큰 파일 쓰게 해서 반려 확인
- **6** · **인라인 컴포넌트**(P0-3)
  판정 단위 결정 후(3장) 컴포넌트 2개짜리 파일 반려 확인
- **7** · 조정 (임계값 · 예외 경로) — `.fe-harness.json` 확정
- **8** · **그냥 쓰기** — 짜증난 순간 전부 11장에 기록 ← 진짜 산출물

2번이 P0-1(포맷)부터인 이유: `PostToolUse`라서 8장 ①의 전제와 **무관하다.**
답을 기다릴 필요가 없는 일을 먼저 한다.

**마지막 8번이 핵심이다.** 마찰 기록이 v0.2 스펙이자 블로그 글 재료다.
"만들어봤다" 글은 널렸고 "쓰다가 이게 불편해서 이렇게 바꿨다" 글은 드물다.
8번은 끝나는 단계가 아니라 계속 도는 단계다 — 조정할 때마다 5·6·7로 돌아간다.

**스킬과 서브에이전트는 훅이 다 돌아간 뒤에 시작한다.** 훅은 디버깅이 결정적이라
만들면 바로 효과가 보이지만, 스킬은 프롬프트 튜닝이라 끝이 없어서 먼저 손대면
거기서 못 빠져나온다.

---

## 10. 공개 기준

- [ ] 현업 저장소에서 **실사용** — 안 쓰는 도구는 만든 게 아니다.
      기간이 아니라 **11장에 조정 기록이 쌓이고 새 마찰이 더 안 나오는 것**이 기준
- [ ] `claude plugin validate ./fe-harness --strict` 통과
- [ ] **서로 다른 저장소 2개**에서 동작 확인 (범용성 주장의 근거)
- [ ] 모든 훅 스크립트 `chmod +x`
- [ ] 정책 훅 첫 실행에 `Failed with non-blocking status code` 없음
- [ ] README에 **「설계 판단과 포기한 것」** + **「알려진 한계」** 존재
- [ ] LICENSE (MIT)
- [ ] ⚠️ 현업 저장소의 로그 · 저널은 절대 커밋하지 않는다

### README에 반드시 들어갈 「설계 판단과 포기한 것」 후보

전부 이 문서에 근거가 있다.

- 왜 저장소 전체가 아니라 파일 1개만 포맷하는가
  → 느리면 결국 끄게 되니까
- 왜 새 파일과 기존 파일의 임계값이 다른가
  → 새 파일 만들기를 싸게 만들려고
- 왜 코드 품질 기준을 정의하지 않는가
  → 훅은 셀 수 있는 것만 판단한다. 읽어야 아는 것은 리뷰 시점 도구의 몫이고,
  같은 층위를 두 벌 얹으면 충돌한다 (4장)
- 왜 flag props는 차단이 아니라 경고인가
  → 정당한 경우가 실제로 있다
- 왜 자동 호출 스킬이 하나도 없는가
  → 전부 내가 의도해서 부르는 작업이다

### 「알려진 한계」 후보

- Tailwind 기본 팔레트 이탈은 못 잡는다 (hex / arbitrary value만)
- 클래스 컴포넌트 미지원
- flag props는 타입 멤버 구분자가 `;`일 때만 잡는다 (콤마 구분은 미탐, 5장)
- `Edit`은 파일 전문이 오지 않아 컴포넌트 카운트의 판정 단위가 `Write`와 다르다 (3장)
- `jq` 의존. 없으면 전체 no-op
- Windows는 WSL 기준으로만 확인
- eval 하니스 없음 (v0.2 예정)

---

## 11. 사용 후 조정 기록

**이 문서에서 제일 값이 나가는 절이 될 곳이다.** 4장의 임계값도 3장의 반려/경고
구분도 전부 근거 없는 첫 값이고, 여기 쌓이는 기록만이 그걸 고칠 근거가 된다.

기록 기준은 하나 — **거슬린 순간.** 훅이 막았는데 내가 옳았던 경우, 훅이
통과시켰는데 막았어야 했던 경우, 그냥 성가셨던 경우. 셋 다 적는다.
특히 **"이거 그냥 끄고 싶다"**는 생각이 든 순간은 반드시 적는다 — 짜증나는 훅은
결국 꺼지고, 꺼진 훅은 만든 게 아니다.

| 날짜 | 무엇이 걸렸나 / 안 걸렸나 | 어떻게 바꿨나 |
| --- | --- | --- |
| _(아직 없음 — 9장 3번 이후 시작)_ | | |

**바꾼 게 있으면 해당 장도 같이 고친다.** 이 표만 늘어나고 본문이 그대로면
문서가 현실과 어긋나기 시작한다.
