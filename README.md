# fe-harness

**FE 코드 품질 루프.** 커밋과 푸시 시점에 코드를 검증하고 리뷰한다.
같은 지적이 반복되면 그걸 규칙으로 올린다 —
**루프가 돌수록 지적이 줄어드는 것**이 이 도구의 목표다.

| 시점 | 보는 범위 | 하는 일 |
| --- | --- | --- |
| **커밋할 때** | 이번 변경만 | 검증 · 리뷰 · 개선 · 기록 |
| **푸시할 때** | 브랜치 전체 | 커밋 사이에 생긴 문제 · 반복된 지적의 규칙화 |

**스킬 · 훅 · 서브에이전트를 플러그인 내부에 직접 구현하지 않는다.**
마켓플레이스에서 검증된 것들을 **역할에 맞게 끼워서** 쓰고,
무엇을 끼울지는 설정 한 줄로 바꾼다.

🚧 **개발 중.** 왜 이렇게 만들었는지: [docs/DESIGN.md](docs/DESIGN.md)

---

## 무엇을 해 주나

커밋하면 자동으로 네 단계가 돈다. 백그라운드로 돌아 작업을 막지 않고,
결과만 다음 턴에 넘어온다. FE 파일이 안 바뀐 커밋은 건너뛴다.

| 단계 | 무엇을 보나 | 누가 판단하나 |
| --- | --- | --- |
| **① verify** | **정답이 있는 것** — 중복이 늘었는가, 타입·린트·테스트가 통과하는가 | 프로그래밍 도구 |
| **② review** | **읽어야 아는 것** — 이 컴포넌트가 두 가지 일을 하는가 | 모델 |
| **③ refine** | 지적을 고칠 수정 코드까지 제시 | 적용 여부는 사람 |
| **④ learn** | `findings.md` 에 한 줄 기록 | — |

푸시할 때는 브랜치 전체를 한 번 더 본다 — 내부 루프는 그 시점의 단일 커밋만
보므로, 커밋 A 와 커밋 C 사이에 생긴 중복은 여기서 잡힌다.

| | 커밋할 때 (내부) | 푸시할 때 (외부) |
| --- | --- | --- |
| 보는 범위 | 이번 커밋 | 브랜치 전체 |
| 중복·죽은 코드 | 몇 건 늘었는지 | 총 몇 건인지 |
| 승격 제안 | 안 함 | **함** |
| 비용 | ~1분 | 수 분 |

### 반복된 지적은 규칙이 된다

지적 → `findings.md` 에 카테고리와 함께 기록 → 같은 카테고리 **3회** → 승격 제안

| 지적의 성격 | 어디로 올리나 |
| --- | --- |
| 기계적으로 판정 가능 | `hookify` 규칙 (block / warn) |
| 판단이 필요한 지침 | `CLAUDE.md` |
| 이 저장소만의 맥락 | `.fe-harness.json` 의 `guidance` |

- **제안만 한다.** 확인 없이 규칙을 추가하지 않는다
- **승격한 항목은 카운트에서 뺀다.** 같은 걸 매번 물으면 결국 끄게 된다
- **승격 뒤 새로 3회 쌓이면 다시 제안한다.** 규칙이 부족했다는 신호다

### 잘 되고 있는지 보는 법

**커밋당 새로 나오는 지적 수가 줄어드는가.** 이게 유일한 지표다.
`.fe-harness/findings.md` 는 계기판이므로 커밋하는 것을 권한다 —
히스토리가 없으면 추세를 볼 수 없고, 3회 카운트도 세션을 넘겨 쌓여야 한다.
로컬에만 두려면 `.gitignore` 에 `.fe-harness/` 를 추가하면 되지만,
그러면 팀이 같은 지적을 각자 3번씩 받는다.

---

## 설치

**사용할 플러그인의 마켓플레이스를 먼저 등록.** (의존성 미해결 시 플러그인 비활성)

```bash
claude plugin marketplace add toss/frontend-fundamentals
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add masuP9/a11y-specialist-skills

claude plugin marketplace add Junsuu/fe-harness
claude plugin install fe-harness@fe-harness

claude plugin list      # Status 확인
```

설치 후 한 번:

```
/fe-harness:setup       # 저장소를 훑어 .fe-harness.json 을 만든다
```

- 마켓만 등록돼 있으면 의존 플러그인(`frontend-fundamentals` · `hookify` · `commit-commands` · `a11y-specialist-skills`)은 **자동 설치**
- **기본 설정에 적힌 도구는 전부 필수.** 하나라도 없으면 플러그인이 비활성화된다
- **`validate --strict` 는 로드 성공을 보장하지 않는다.** `claude plugin list` 의 `Status` 를 봐야 한다

## 사용법

```
/lap               품질 루프 한 바퀴 — 아직 리뷰 안 된 가장 최근 변경
/lap push          푸시 전 — 브랜치 전체
/fe-harness:setup  설정 생성 (설치 후 한 번)
```

커밋·푸시하면 같은 루프가 **자동으로** 돈다. `/lap` 은 손으로 부르고 싶을 때
쓰는 같은 절차다.

---

## 설정

프로젝트 루트의 `.fe-harness.json`. **없어도 동작한다.**
`/fe-harness:setup` 이 만들어 주므로 직접 쓸 필요는 없다.

| 상태 | 동작 |
| --- | --- |
| 파일이 있다 | 그대로 쓴다. 추론하지 않는다 |
| 파일이 없다 | 린터 · 포매터를 추론한다 |
| 추론도 실패 | 아무것도 하지 않는다 |

전체 예시는 [`.fe-harness.example.json`](.fe-harness.example.json).

```json
{
  "roles": {
    "guide":  ["frontend-fundamentals:readability", "frontend-fundamentals:cohesion"],
    "review": ["frontend-fundamentals:reviewer", "a11y-specialist-skills:reviewing-a11y"],
    "refine": "",
    "record": "commit-commands:commit",
    "learn":  "hookify"
  },
  "verify": {
    "typecheck": "pnpm typecheck",
    "duplication": "npx jscpd --min-lines 8 --reporters json --silent",
    "deadcode": "npx knip --reporter json"
  }
}
```

### `roles` — 루프의 각 단계에 어떤 도구를 끼울지

| 역할 | 하는 일 | 기본값 |
| --- | --- | --- |
| `guide` | 쓰기 **전에** 기준을 컨텍스트에 넣는다 | `frontend-fundamentals` 스킬 |
| `review` | 읽어야 아는 것을 본다 | `frontend-fundamentals:reviewer` + `a11y-specialist-skills:reviewing-a11y` (병렬) |
| `refine` | 지적을 수정 코드로 옮긴다 | 없음 (모델이 직접) |
| `record` | 커밋·PR 문구를 요점만 쓴다 | `commit-commands` |
| `learn` | 반복된 지적을 규칙으로 올린다 | `hookify` |

| 쓰는 값 | 뜻 |
| --- | --- |
| `"frontend-fundamentals:reviewer"` | 이 도구를 쓴다 |
| `["도구A", "도구B"]` | 둘 다 쓴다 (`review` 만 해당, 병렬) |
| `""` | 도구 없이 모델이 직접 한다 |
| 키를 안 씀 | 위 표의 기본값을 쓴다 |

단계를 아예 끄려면 `disable` 을 쓴다. `""` 는 끄기가 아니다 —
도구만 안 쓸 뿐 단계는 그대로 돈다.

### `verify` — 프로그램이 판정하는 검사

| 키 | 언제 도나 | 비우면 |
| --- | --- | --- |
| `format` · `lint` | 파일을 쓸 때마다 | prettier / eslint / biome 를 추론 |
| `typecheck` · `test` | 턴이 끝날 때 (실패 시 종료 차단) | 안 돈다 |
| `duplication` · `deadcode` | 루프에서 | 안 돈다 |
| `a11yRuntime` | 외부 루프에서 | 안 돈다 |

`format` · `lint` 외에는 **명시했을 때만** 돈다. 추측한 `test` 가 몇 분짜리
통합 테스트일 수도 있기 때문이다. `/fe-harness:setup` 이 넣기 전에 물어보는
이유이기도 하다.

### `signals` — 차단 없는 경고 기준

```json
{ "signals": { "maxNewFileLines": 250, "maxEditLines": 80, "maxComponentsPerFile": 1 } }
```

넘으면 경고만 한다. **차단하는 훅은 하나도 없다** — 데이터 테이블 · 타입 정의 ·
SVG 처럼 정당하게 긴 파일이 실재하기 때문이다. 그 개수가 문제인지는 review 가
판단한다.

### `trigger` · `disable` · `guidance`

```json
{
  "trigger":  { "commit": true, "push": true },
  "disable":  { "signals": true },
  "guidance": "쪼개기 전에 이 저장소의 컴포넌트 배치 규칙을 확인할 것"
}
```

- `trigger` — 커밋·푸시 자동 실행을 시점별로 끈다. `/lap` 은 그대로 쓸 수 있다
- `disable` — `guide` · `format` · `lint` · `gate` · `verify` · `signals` · `loop` 를 각각 끈다
- `guidance` — 리뷰·경고 메시지 끝에 붙는 한 줄. 저장소만의 맥락을 둔다

---

## 항상 도는 것 (루프 밖)

매 편집마다 도는 훅. **전부 신호이고 차단은 없다.**

| 훅 | 시점 | 동작 |
| --- | --- | --- |
| 포맷 | `Write`/`Edit` 후 | 편집된 파일 1개만 포맷 |
| 린트 피드백 | `Write`/`Edit` 후 | `--fix` 후 남은 문제를 그 턴 안에 |
| 분량 · 컴포넌트 신호 | `Write`/`Edit` 후 | 기준을 넘으면 경고 |
| 품질 게이트 | 턴 종료 시 | 타입체크·테스트 실패면 **종료 차단** |
| 지침 주입 | 세션 시작 | 기준을 컨텍스트에 한 줄로 |

## 알려진 한계

- **실사용 기록이 아직 적다.** 3회 승격 기준과 카테고리 목록이 맞는지,
  매 커밋 트리거가 성가신 수준인지는 아직 안 겪어봤다
- **`guide` 역할이 미완이다.** 무엇을 주입할지는 `findings` 가 쌓인 뒤에 정한다
- **a11y 런타임 검사는 없다.** 대비 · 포커스 순서는 렌더가 필요해 다루지 않는다.
  정적 검사는 `eslint-plugin-jsx-a11y` 추가 제안, 판단 리뷰는 `a11y-specialist-skills` 가 맡는다
- **같은 컴포넌트를 감싸기만 한 경우도 2개로 센다.**
  `const Base = forwardRef(...)` 뒤에 `export const X = memo(Base)`. 오탐이다
- **클래스 컴포넌트 미지원.**
- **한 턴 전체의 변경량은 보지 않는다.** 240줄짜리 파일 10개를 써도 신호가 안 난다
- **`jq` 의존.** 없으면 전체 no-op
- **Windows 는 WSL 기준으로만 확인.** macOS 기본 bash 3.2 에 맞춰 작성했다

## 개발

```bash
./test.sh                          # 회귀 테스트
claude plugin validate . --strict
```

설계와 근거, 훅 작성 규칙, 디버깅: [docs/DESIGN.md](docs/DESIGN.md)

## 라이선스

MIT. [LICENSE](LICENSE) 참조.
