# fe-harness — 설계 문서

> Claude Code 플러그인. AI 코딩 세션에서 **코드가 써지는 시점에** 품질을 통제한다.
>
> 저자: tinyhex · 작성 2026-08-17 · 최종 갱신 2026-08-18 · 기준 Claude Code v2.1.231
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

| 레이어          | 수단                            | 결정성   | 컨텍스트 비용      |
| --------------- | ------------------------------- | -------- | ------------------ |
| 항상 아는 사실  | `CLAUDE.md`                     | 권고     | 매 요청 전량       |
| 경로별 규칙     | `.claude/rules/*.md` + `paths:` | 권고     | 매칭 시에만        |
| 절차 / 레퍼런스 | Skills                          | 권고     | description만 상주 |
| **강제**        | **Hooks**                       | **보장** | **0**              |
| 격리 검증       | Subagents                       | 권고     | 별도 컨텍스트      |

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

> ✅ **검증됨** (2026-08-18) — `content`는 잘리지 않고 전문으로 온다.
> 바이트 단위로 실제 파일과 일치함을 확인했다. 8장 ① 참조.

> ⚠️ **`Edit`은 파일 전문이 오지 않는다.** `new_string`은 교체 조각이다.
>
> 분량 게이트(P0-2)는 "이번 턴에 얼마나 붙이는가"를 재므로 조각 기준이 맞다.
> 그러나 컴포넌트 카운트(P0-3)는 **파일 전체 기준**이어야 한다 — 두 번째
> 컴포넌트를 `Edit`으로 끼워 넣으면 `new_string`엔 1개만 보이고 파일엔 2개가 된다.
>
> 이건 위 항목과 무관하게 발생한다. 대응은 4장 P0-3 참조.

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
- **3 · 인라인 컴포넌트** — 증상 ⑤
  `Write` → `PreToolUse` **반려** / `Edit` → `PostToolUse` **경고**

**P0-3은 도구별로 층이 다르다.** 3장의 경고대로 판정 단위가 다르기 때문이다.

| | 스크립트 | 이벤트 | 셀 수 있는 것 | 결과 |
| --- | --- | --- | --- | --- |
| `Write` | `guard-components.sh` | `PreToolUse` | `content` = 파일 전문 | **반려** |
| `Edit` | `warn-components.sh` | `PostToolUse` | 완성된 파일을 읽음 | **경고** |

**왜 `Edit`은 경고인가** — `PreToolUse`에서 `Edit`이 주는 건 조각뿐이라 파일에
컴포넌트가 몇 개가 될지 알 수 없다. 정확히 세려면 파일이 써진 뒤여야 하고,
그때는 이미 되돌릴 수 없다. **정확하지만 늦거나, 이르지만 부정확하거나** —
후자를 택했다.

**왜 그래도 괜찮은가** — 증상 ⑤는 대부분 새 파일을 쓸 때 생긴다. 기존 파일에
두 번째 컴포넌트를 `Edit`으로 끼워 넣는 건 상대적으로 드물다. 흔한 경로를 막고
드문 경로는 경고로 두고 실사용 기록을 본다(11장).

**임계값 의미** — `maxComponentsPerFile`은 **허용 최대 개수**이고 기본값은 **1**이다.
설정 예시가 한때 2로 적혀 있었는데 "2개 이상이면 반려"와 어긋났다. 1로 통일한다.

**포맷이 P0인 이유** — Claude가 `Write`로 만든 파일은 **에디터의 저장 이벤트를
안 거친다.** format-on-save가 걸려 있어도 적용되지 않는다. 포맷 안 된 코드가 섞인
diff는 사람이 검토할 수 없고, 그게 이 프로젝트의 목표를 정면으로 깬다.

**분량 게이트의 임계값은 비대칭이어야 한다:**

```
Write (새 파일)   : 250줄   ← 새 파일 만들기를 "싸게"
Edit  (기존 수정) :  80줄   ← 기존 파일에 붙이기를 "비싸게"
```

이게 1장의 처방을 그대로 구현한 것이다.

**이 숫자는 이제 근거가 있다** (2026-08-18 실측, 현업 저장소 5개 —
파일 생성 8,467건 · 수정 24,976건. `tools/measure-thresholds.sh`로 재현 가능):

| | p50 | p75 | p90 | p95 | p99 |
| --- | --- | --- | --- | --- | --- |
| 생성 시 크기 | 49 | 95 | 174 | **244** | 437 |
| 수정 시 추가 | 4 | 12 | 33 | **59** | 163 |

**측정 대상을 고르는 게 절반이다.** 현재 파일 크기를 재면 안 된다 — 600줄
파일은 처음부터 600줄로 태어나지 않는다. `maxNewFileLines`의 비교 대상은
**파일이 처음 만들어질 때의 크기**(`--diff-filter=A`)이고, `maxEditLines`의
비교 대상은 **수정 커밋에서 추가된 줄 수**(`--diff-filter=M`)다.

**250은 맞았다.** 정확히 p95(244)에 앉는다. 그대로 둔다.

**150은 틀렸다 — 설계 의도와 반대로 작동하고 있었다.** 절대값만 보면
250 > 150 이라 비대칭인 것 같지만, 각자의 분포에 비추면 정반대다:

```
새 파일 250줄 → p95    (상위 5%)     촘촘함
수정   150줄 → p98.5  (상위 1.2%)   헐렁함   ← 기존 파일 쪽이 더 후했다
```

수정은 원래 작다 — 중앙값 4줄, p90 이 33줄이다. 한 번에 150줄을 붙이는 건
이미 예외적 사건이라 게이트가 사실상 안 걸렸다. 게다가 이 측정은 커밋 단위라
실제보다 과대평가다(한 커밋에 여러 번의 `Edit`이 들어간다).

**80으로 내린다.** 저장소별 p95 가 38~72 라 80 은 전부 위에 있어 오탐이 적고,
지금보다 두 배 촘촘하다. 여기서도 안 걸리면 60 → 40 으로 조인다. 한 번에 40 으로
가면 마찰이 커서 게이트를 꺼버릴 위험이 있다(7장).

**저장소마다 분포가 다르다** — 생성 시 p50 이 37~65 로 갈린다. 하나의 기본값이
모든 저장소에 맞을 수 없다는 뜻이고, `harness-doctor`(P2-12)가 저장소별로
이걸 재서 `.fe-harness.json` 초안을 만들어야 한다는 근거다.

### P1 — P0가 실제로 돌아간 뒤

- **4 · 품질 게이트** — `Stop` · 안전망
  tsc + 변경분 테스트 통과 전 종료 차단
- ~~**5 · flag props**~~ — **폐기.** 이유는 아래 「의도적으로 하지 않는 일」
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
  ⚠️ 착수 전 확인: 기본 탑재 `simplify` 스킬이 이미 "변경분 검토 후 **수정 적용**"을
  한다. 리뷰 도구에 수정 권한이 없는 경우를 메우려던 항목이니, 그걸로 충분하면
  만들지 않는다
- **12 · `harness-doctor` 스킬** — 새 저장소 진단
- **13 · eval 케이스와 채점 기준** — 임계값이 근거를 갖게 만드는 유일한 수단
  하니스는 만들지 않는다. `claude plugin eval`이 이미 `evals/**/case.yaml`
  (또는 `prompt.md` + `graders/*.md`)를 돌리고 **no-plugin baseline arm 을
  자동으로 추가**한다. 우리가 쓸 것은 케이스와 채점 기준뿐이다

### 의도적으로 하지 않는 일

**fe-harness는 코드 품질 기준을 정의하지 않는다.** 훅은 셀 수 있는 것만 판단할 수
있고(7장), 응집도나 이름이 동작과 맞는지는 읽어야 아는 것이다.
선은 회사나 도구가 아니라 **강제 가능성**으로 긋는다.

```
셀 수 있는 것   → 스크립트 · 작성 시점 · 강제   ← fe-harness 가 하는 것
                  줄 수, 컴포넌트 개수, boolean prop 개수, hex 리터럴

읽어야 아는 것  → 모델 · 리뷰 시점 · 권고      ← fe-harness 밖
                  응집도, 결합도, 예측 가능성, 이름의 적절성
```

P2-8(토큰 하드코딩)은 이 선의 왼쪽이다 — 품질 의견이긴 하지만 hex 리터럴은
**셀 수 있으니까** 훅이 할 수 있다. 반대로 셀 수 없는 것은 아무리 중요해도
이 저장소에 넣지 않는다.

**오른쪽은 fe-harness의 책임이 아니다.** 리뷰 시점 도구로 채우든, 사람이 눈으로
보든, 아무것도 안 채우든 **fe-harness의 동작은 같다.** 단독 설치로도 자기 일은
전부 한다 — 변경을 검토 가능한 크기와 모양으로 유지하는 것.

> **의존성 없음.** 이 문서에 나오는 다른 플러그인·스킬 이름은 전부 **예시이자
> 참고**다. fe-harness는 어떤 것도 요구하지 않고, 설치 여부를 확인하지도 않으며,
> 없어도 동작이 달라지지 않는다.
>
> 범위는 **자기 능력으로** 정의한다. 남이 무엇을 하는지로 정의하면, 그 남이
> 사라질 때 이 문서의 근거도 같이 사라진다.

같이 쓸 때의 주의만 하나 적어둔다 — 같은 층위의 규칙을 두 벌 얹지 말 것.
스킬 본문은 한 번 호출되면 세션 내내 컨텍스트에 남으므로 비용이 두 배가 되고,
충돌할 때 Claude가 임의로 하나를 고른다.

#### flag props 경고를 폐기한 이유 (P1-5)

**개수가 문제 여부를 말해주지 않는다.** Button의 `disabled` + `loading`은
boolean 2개지만 완벽하게 정상이다. `showHeader` + `isCompact`는 같은 개수인데
분기를 컴포넌트로 안 뺀 신호다. **둘을 구분하려면 읽어야 한다.**

즉 flag props는 위 선의 **왼쪽 절반만** 할 수 있는 항목이다 — 개수는 세지지만
그 개수가 문제인지는 못 판단한다. 그래서 경고로 내렸던 것인데, 경고도 정상 코드에서
계속 뜨면 모델은 무시하는 걸 배우고 사용자는 훅을 끈다. 이 프로젝트가 제일
경계하는 실패다(7장 「차단 vs 경고 판단」).

증상 ④는 선의 오른쪽으로 넘긴다. 콤마 구분자 미탐(5장)은 폐기 이유가 아니다 —
그건 정규식 한 글자 수정이면 된다.

#### 스킬로도 "좋은 아키텍처"를 정의하지 않는다

훅으로 못 하는 판단(어떤 컴포넌트로 쪼갤지, 어떤 패턴을 쓸지)은 스킬의 영역이
맞다. 하지만 **범용 원칙을 담은 스킬은 이미 생태계에 여러 벌 있다** — 리뷰 스킬
모음, Claude Code 기본 탑재 `simplify`(변경분 검토 후 수정 적용)나 `Plan`
서브에이전트(구현 전 설계·단계 분해) 같은 것들. 한 벌 더 쓰면 위에 적은
"같은 층위 두 벌" 문제를 우리가 직접 만드는 셈이다.

fe-harness가 스킬로 채울 빈칸은 **"우리가 왜 막았고 그래서 뭘 하라는 건가"**다.
왜 막았는지는 우리만 알고 아무도 대신 알려줄 수 없다.
이건 "좋은 코드란 무엇인가"가 아니므로 위 원칙과 충돌하지 않는다 —
**의존성을 만드는 게 아니라 자기 기능을 완성하는 것이다.**

**훅과 스킬은 이어붙인다.** 훅의 stderr는 모델이 읽는 프롬프트다(7장).
분량 게이트가 반려할 때 stderr에 "쪼개기 전에 이 스킬을 먼저 호출하라"를 쓰면,
**훅이 트리거 · 스킬이 판단**이 된다. 훅은 "지금이 그 판단을 할 시점"이라는 것만
결정적으로 보장한다.

단, **가리키는 스킬은 반드시 fe-harness 안에 있어야 한다**(7장).

#### 그 절차 스킬은 아직 만들지 않는다 — 조건부

필요하다는 증거가 아직 없다. P0-2의 첫 버전은 stderr 문구만으로 간다:

```
400줄은 250줄 제한을 넘습니다.
컴포넌트 단위로 파일을 나눠서 각각 Write 하세요.
```

이걸로 모델이 제대로 대응하면 스킬은 필요 없다. **엉뚱하게 대응하는 게 반복되면**
— 한 파일을 두 번에 나눠 쓰는 식으로 우회한다든지 — 그게 스킬이 필요하다는
증거이고, 11장 조정 기록의 항목이 된다. 그때 근거를 갖고 만든다.

9장의 경고와도 같은 방향이다: 스킬은 프롬프트 튜닝이라 끝이 없어서
먼저 손대면 거기서 못 빠져나온다.

#### 예방은 스킬의 일이 아니다

교정보다 예방이 낫다는 건 맞다 — 막고 다시 쓰게 하는 것보다 처음부터 제대로
쓰게 하는 쪽이 싸다. 그런데 **스킬은 예방 채널이 아니다.** 본문은 호출해야
로드되고, 우리는 자동 호출을 전부 끈다. 그래서 지금 구조는 이렇다:

```
쓴다 → 막힌다 → 스킬 로드 → 다시 쓴다      교정
스킬 로드 → 쓴다                           예방  ← 이건 스킬로 안 된다
```

**stdout 이 컨텍스트로 가는 이벤트는 `SessionStart`·`UserPromptSubmit`·
`UserPromptExpansion` 셋뿐이다**(7장). P1-7 을 컴팩션 재주입 용도로만
생각했지만, **같은 메커니즘이 유일한 예방 채널**이다.

그래서 분량으로 갈린다:

- **한 줄로 되는 것** → 주입.
  `"컴포넌트는 파일당 하나. 새 파일 만들기를 아끼지 말 것"` — 토큰 10개,
  항상 present, 스킬 불필요
- **절차가 필요한 것** → 스킬.
  "이 저장소에서 필터·테이블·페이지네이션을 어느 디렉터리에 두는가"

2026-08-18 실험에서 모델이 stderr 세 줄만으로 헤매지 않고 쪼갠 걸 보면,
**한 줄 주입으로 충분할 가능성이 높다.** 스킬 한 벌을 세션 내내 지고 다니는
것보다 훨씬 싸다.

**다만 이건 추측이고 논증으로 못 정한다.** P2-13 eval 의 첫 케이스로 잡는다:

```
Arm A  주입 없음   → 반려 1회, 9파일 (2026-08-18 실측, baseline)
Arm B  한 줄 주입  → 첫 Write 부터 쪼개져 나오나?
Arm C  절차 스킬   → B 보다 나은가?
```

`claude plugin eval` 이 baseline arm 을 자동으로 붙이므로 A 는 공짜다.

**그 외에 안 만드는 것**

- 자동 호출 스킬 — P0~P2 전부 `disable-model-invocation: true`
- 포맷 이외의 스타일 규칙 — 린터 영역

### 참고한 구현 — 의존이 아니라 인용

P2-13 eval을 만들 때 쓸 아이디어 3개. `toss/frontend-fundamentals` 저장소를 읽고
배운 것이고, **그 플러그인이 설치돼 있어야 한다는 뜻이 아니다.**

- `agents/reviewer.md`의 **스킬 로딩 강제 프롬프팅**
  "STOP - Read This First" + 변명별 반박 표
- `eval/graders/grader.md`의 **`Must NOT Suggest`** 절
  과잉 엔지니어링 제안을 감점 처리
- ~~eval의 **baseline vs with-skill 비교** 설계~~
  빌릴 필요 없다 — `claude plugin eval`이 baseline arm 을 기본으로 붙인다

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

### `fh_flag_props` — 현재 소비자 없음

이 함수를 쓰려던 P1-5 훅은 폐기했다(4장). 함수와 테스트는 남긴다:

- 콜백 인자의 boolean 을 제외하는 부분이 실제로 디버깅한 결과물이다
- P2-8 토큰 하드코딩도 같은 방식의 블록 스캔이 필요하다

P2 착수 시점에도 소비자가 없으면 그때 지운다. **조용히 죽은 코드로 남기지 않는다.**

알려진 미탐: 멤버 구분자가 `;`일 때만 잡는다.
`type BannerProps = { a: boolean, b: boolean }`처럼 콤마로 구분하면 놓친다.
쓸 곳이 생기면 awk 패턴의 `;?`를 `[;,]?`로 바꾸면 된다.

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

**흔한 실수** — `hooks/`, `skills/`, `agents/`를 `.claude-plugin/` **안에** 넣는 것.
매니페스트만 그 안에 들어간다.

### 현재 (P0 진행 중)

```
fe-harness/
├── .claude-plugin/
│   ├── plugin.json          ← 이 폴더엔 매니페스트만
│   └── marketplace.json
├── hooks/
│   ├── hooks.json           ← format.sh + guard-size.sh
│   └── scripts/
│       ├── lib-detect.sh    ← 5장, 검증 완료
│       ├── lib-config.sh    ← 설정 3단 폴백 · exclude · 확장자
│       ├── format.sh            ← P0-1 ✅
│       ├── guard-size.sh        ← P0-2 ✅ 반려
│       ├── guard-components.sh  ← P0-3 ✅ 반려 (Write)
│       └── warn-components.sh   ← P0-3 ✅ 경고 (Edit)
├── fixtures/                ← 탐지 로직 테스트 데이터 8개
├── tools/
│   └── measure-thresholds.sh  ← 임계값 근거 측정. harness-doctor 의 원형
├── test.sh
├── .fe-harness.example.json
├── docs/DESIGN.md           ← 이 문서
└── README.md
```

### P2까지 다 만들었을 때

```
fe-harness/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── hooks/
│   ├── hooks.json
│   └── scripts/
│       ├── lib-detect.sh          ← 라이브러리 (훅 아님)
│       ├── lib-config.sh          ← 라이브러리 (훅 아님)
│       ├── format.sh              P0-1  PostToolUse
│       ├── guard-size.sh          P0-2  PreToolUse   ★ 반려
│       ├── guard-components.sh    P0-3  PreToolUse   ★ 반려 (Write)
│       ├── warn-components.sh     P0-3  PostToolUse    경고 (Edit)
│       ├── gate-stop.sh           P1-4  Stop         ★ 반려
│       ├── lint-feedback.sh       P1-6  PostToolUse    경고
│       ├── reinject.sh            P1-7  SessionStart
│       └── warn-tokens.sh         P2-8  PostToolUse    경고
├── skills/
│   ├── harness-doctor/            P2-12 새 저장소 진단
│   ├── refactor-pass/             P2-11 ⚠️ 조건부 — 기본 탑재 도구로
│   │                                    충분하면 안 만든다
│   └── split-plan/                조건부 — 반려 대응 절차.
│                                  stderr 만으로 부족하다는 증거가 나오면
├── agents/
│   └── entropy-auditor.md         P2-10 누적 구조 부채 감사
├── evals/                         P2-13 baseline vs with-plugin 비교
├── tools/
│   └── measure-thresholds.sh      임계값 근거 측정
├── fixtures/
├── test.sh
├── .fe-harness.example.json
├── docs/DESIGN.md
├── LICENSE
└── README.md
```

**최대 규모: 훅 스크립트 8개 + 라이브러리 2개 + 스킬 3개 + 서브에이전트 1개.**
그중 스킬 2개는 조건부라 안 만들 수 있다. 반려하는 훅은 3개뿐이고 나머지는
경고이거나 아무것도 막지 않는다.

**플러그인에 들어가지 않는 것**

- **P2-9 `.claude/rules/` + grep 강제** — 프로젝트 쪽이다. 플러그인이 남의
  저장소에 `.claude/rules/`를 심을 수는 없다. README에 예시만 싣는다
- **범용 품질 원칙 스킬** — 4장 「의도적으로 하지 않는 일」
- **`.prettierrc` 같은 포매터 설정** — 하네스는 포매터를 호출할 뿐 정의하지 않는다

**이름이 바뀐 것** — 초안의 `guard-write.sh`(P0-2+P0-3)와 `warn-write.sh`(P1-5+P1-6)는
쪼개졌다. P0-2와 P0-3은 판정 단위가 달라서 한 스크립트에 못 들어가고(3장),
P1-5는 폐기됐다(4장).

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
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/guard-size.sh",
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
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/lint-feedback.sh",
            "args": [],
            "timeout": 60,
            "statusMessage": "린트 확인"
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
  "guidance": "",
  "disable": { "guard": false, "format": false, "warn": false, "gate": false }
}
```

**`disable`을 반드시 넣는다.** 도구가 방해될 때 끌 방법이 없으면 사용자는
플러그인을 삭제한다.

**`guidance`는 커플링을 프로젝트 쪽으로 밀어내는 장치다.** 반려 stderr 끝에
그대로 덧붙는 한 줄이고, 비어 있으면 아무것도 안 붙는다.

```json
{ "guidance": "쪼개기 전에 <이 저장소에 깔린 리뷰 스킬>을 먼저 확인할 것" }
```

플러그인은 어떤 스킬이 깔려 있는지 알 필요가 없고 알아서도 안 된다(7장).
"내 환경엔 저 도구가 있다"는 **사용자의 사실**이지 fe-harness의 사실이 아니므로,
그 지식은 프로젝트 설정에만 둔다.

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
경고 훅은 이걸 쓴다. 다만 화면에는 `PostToolUse:Edit hook blocking error`
라고 뜬다 — **"blocking"이라고 적혀 있어도 실제로 막지 않는다.**
파일은 이미 써져 있다. 실측으로 확인했다(2026-08-18).

**`Stop` 훅**은 `stop_hook_active` 파싱이 필수다(무한 루프).
**연속 8회 차단하면 무시**된다.

**matcher는 대소문자를 구분하고 unanchored다.** `Edit.*`는 `NotebookEdit`에도
걸린다 → `^Edit$`.

**`chmod +x`** 안 하면 조용히 실패한다.

**`hooks/hooks.json`은 자동으로 로드된다.** `plugin.json`에 `"hooks":
"./hooks/hooks.json"`을 또 적으면 중복으로 잡혀 **플러그인 전체가 로드에
실패한다.** `manifest.hooks`는 표준 위치가 아닌 **추가** 훅 파일에만 쓴다.

**`validate --strict` 통과는 로드 성공을 뜻하지 않는다.** 위 중복 사고는
validate 를 통과하고도 훅이 하나도 안 붙었다. 매니페스트 스키마 검사와 런타임
로드는 별개다. 설치 후 반드시 **`claude plugin list`의 `Status`** 를 확인한다.

**경로 오타가 나면 게이트가 조용히 꺼진다.** 첫 실행에서
`Failed with non-blocking status code`가 없는지 확인할 것.

**셸 프로필의 echo.** `.bashrc`의 무조건 `echo`가 stdout 앞에 붙으면 JSON이
통째로 무시된다. exit 0이면 화면에 아무것도 안 뜬다.

**stderr 메시지는 사람이 아니라 Claude가 읽는다.** "Blocked"만 쓰면 우회를
시도한다. **"대신 무엇을 하라"를 반드시 넣는다.**

**훅은 자기 플러그인에 들어 있는 스킬만 가리킨다.** stderr에 없는 스킬 이름을
쓰면 모델은 호출을 시도했다가 실패하고 한 턴을 버린다. 더 나쁜 경우는 **이름만
보고 내용을 짐작해서 진행**하는 것이다 — 지시는 받았는데 본문은 못 읽었으니까.
남의 플러그인 스킬을 가리키는 건 stderr 문자열로 의존성을 만드는 짓이다.
사용자별 조합은 `.fe-harness.json`의 `guidance`로 밀어낸다(6장).

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
  | ./guard-size.sh; echo "exit=$?"
```

---

## 8. 미검증 항목

> **의사결정 (2026-08-17) — 검증을 별도 단계로 두지 않는다.**
>
> 초안은 착수 전에 버릴 훅을 settings에 심어 payload를 뜨는 계획이었다.
> 그런데 그건 `guard-size.sh`가 하는 일과 똑같다. **버릴 훅 대신 진짜 훅의 첫
> 버전을 _관찰 모드_(payload 로깅 후 `exit 0`)로 만들면 검증이 부산물로 나온다.**
> 플러그인 설치 때 어차피 세션 재시작이 필요하니 그 한 번에 합친다.
>
> 틀렸을 때 손해가 작다는 것이 근거다. content가 잘려 와도 버려지는 건
> `guard-size.sh`의 payload 파싱부뿐이고, `lib-detect.sh` · 설정 3단 폴백 ·
> 임계값 로직 · stderr 문구는 전부 살아남는다. 값싼 베팅이라 먼저 걸어본다.

### ① `PreToolUse`의 `tool_input.content`가 전문으로 오는가

✅ **검증 완료** (2026-08-18). **전문으로 온다 — 반려 설계가 살았다.**

100줄 파일을 `Write` 시킨 뒤 payload의 `content`와 실제 파일을 `cmp`로 비교해
**바이트 단위 완전 일치**를 확인했다. `Edit`의 `new_string`은 예상대로
교체 조각만 왔다(3장 ④).

| | `tool_input` 키 |
|---|---|
| `Write` | `content`, `file_path` |
| `Edit` | `old_string`, `new_string`, `replace_all`, `file_path` |

payload 최상위 키도 기록해 둔다 — 나중에 쓸 것이 있다:

```
cwd, effort, hook_event_name, permission_mode, prompt_id,
session_id, tool_input, tool_name, tool_use_id, transcript_path
```

`permission_mode`가 온다는 건 "이 모드에선 게이트를 느슨하게" 같은 게
가능하다는 뜻이다. 지금은 쓰지 않는다.

<details>
<summary>확인 절차 (관찰 모드를 다시 켤 때)</summary>

`.fe-harness.json`에 `"observe": true`를 넣으면 payload가 저장소 밖에 쌓인다.

```bash
DIR=${FE_HARNESS_OBSERVE_DIR:-${TMPDIR:-/tmp}/fe-harness-observe}
ls "$DIR"/payload-*.json

# 판정 — jq -r 은 개행을 덧붙이므로 -j 를 쓴다
jq -j '.tool_input.content' "$DIR/payload-<시각>.json" > /tmp/from-payload
cmp /tmp/from-payload <대상 파일>
```

`Edit`은 조각만 오므로 줄 수를 파일과 비교하면 안 된다.
`keys`에 `new_string`이 있는지, 그 값이 잘리지 않았는지만 본다.

</details>

### ② macOS의 BSD `grep`/`awk`에서 탐지 로직이 동일하게 동작하는가

✅ **검증 완료** (2026-08-17). `./test.sh` 전부 통과.
환경과 발견한 한계는 5장에 기록.

### ③ 클래스 컴포넌트

`class Foo extends Component` — 현재 미지원. 쓰지 않으면 무시.

### ④ `Edit`의 `new_string`은 파일 전문이 아니다

✅ **확정된 사실.** 실측으로도 확인했다(①의 표).
대응은 4장 P0-3 — `Write`는 `PreToolUse` 반려, `Edit`는 `PostToolUse` 경고로 갈랐다.

---

## 9. 작업 순서

**만들면서 하나씩 검증한다.** 8장의 의사결정에 따라 별도 검증 단계는 없다.

- ~~**0** · 미검증 2개 확인~~ — 폐기. 각 훅에 흡수 (8장)
- ✅ **1** · 탐지 로직 + 회귀 테스트 — `test.sh` 통과
- ✅ **2** · 폴더 골격 + 매니페스트 + **포맷 훅**(P0-1)
  `claude plugin validate --strict` 통과 + 포맷 훅 케이스 통과
- ✅ **3** · 설치 + 세션 재시작
  `claude plugin list` Status 정상. `plugin.json` 중복 hooks 참조로 한 번 실패(7장)
- ✅ **4** · `guard-size.sh` **관찰 모드** → 8장 ① 판정 완료. **전문으로 온다**
- ✅ **5** · **분량 게이트**(P0-2) 반려 로직 부착
  실사용 확인 완료 — 255줄 `.tsx` `Write` 가 실제로 취소됐다
- ✅ **6** · **인라인 컴포넌트**(P0-3)
  실사용 확인 완료 — `Write` 2개는 취소, `Edit` 2개는 써지고 경고
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
- [x] `claude plugin validate ./fe-harness --strict` 통과
- [x] `claude plugin list`의 `Status`가 실패가 아님 — validate 통과와 별개다(7장)
- [x] 기본 임계값이 실측 근거를 가질 것 — `tools/measure-thresholds.sh` 결과를 4장에 기록
- [ ] **서로 다른 저장소 2개**에서 동작 확인 (범용성 주장의 근거)
- [ ] **다른 플러그인이 하나도 없는 환경에서 단독 동작** 확인 — 의존성 없음의 근거
- [x] 모든 훅 스크립트 `chmod +x`
- [x] 정책 훅 첫 실행에 `Failed with non-blocking status code` 없음
- [x] README에 **「설계 판단과 포기한 것」** + **「알려진 한계」** 존재
- [x] LICENSE (MIT)
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
- 왜 flag props 경고를 아예 안 만들었는가
  → 개수는 셀 수 있지만 그 개수가 문제인지는 읽어야 안다. `disabled` + `loading`은
  정상이다. 정상 코드에서 계속 뜨는 경고는 결국 꺼진다 (4장)
- 왜 자동 호출 스킬이 하나도 없는가
  → 전부 내가 의도해서 부르는 작업이다

### 「알려진 한계」 후보

- Tailwind 기본 팔레트 이탈은 못 잡는다 (hex / arbitrary value만)
- 클래스 컴포넌트 미지원
- `Edit`은 파일 전문이 오지 않아 컴포넌트 카운트의 판정 단위가 `Write`와 다르다 (3장)
- 같은 컴포넌트를 감싸기만 한 경우도 2개로 센다 — `const Base = forwardRef(...)`
  뒤에 `export const X = memo(Base)`. 오탐이고, 반려 훅이라 비용이 크다.
  실사용에서 얼마나 걸리는지 11장에 기록하고 판단한다
- `Edit`로 두 번째 컴포넌트를 끼워 넣는 경로는 반려가 아니라 경고다 (4장 P0-3)
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

| 날짜                              | 무엇이 걸렸나 / 안 걸렸나 | 어떻게 바꿨나 |
| --------------------------------- | ------------------------- | ------------- |
| _(아직 없음 — 9장 3번 이후 시작)_ |                           |               |

**바꾼 게 있으면 해당 장도 같이 고친다.** 이 표만 늘어나고 본문이 그대로면
문서가 현실과 어긋나기 시작한다.
