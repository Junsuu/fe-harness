# fe-harness

**FE 코드 품질 루프.** 조각을 만들지 않고, 이미 잘 만들어진 훅·스킬·에이전트를
**역할에 끼워** 커밋·푸시마다 한 바퀴 돌린다.

🚧 **개발 중.** 설계와 근거: [docs/DESIGN.md](docs/DESIGN.md)

---

## 왜

Claude Code로 몇 주 작업하면 FE 코드가 이렇게 된다 — 컴포넌트가 비대해지고,
중복이 생기고, 한 파일이 여러 역할을 지고, 가독성이 떨어진다.

v1은 원인을 "파일이 길어지는 것"으로 보고 훅으로 막았다. **실측으로 틀렸다는
게 드러났다** — 정상 `.tsx`의 5~31%가 컴포넌트 2개 이상이었고, 막히는 것들이
아이콘 배럴 같은 정당한 패턴이었다. 길이는 증상이지 원인이 아니다.

**진짜 원인은 만들기만 하고 되돌아보지 않는 것이다.**

```
지금:  설계 → 작성 → 커밋 → 설계 → 작성 → 커밋 …     열화가 누적된다
필요:  설계 → 작성 → 검증 → 리뷰 → 개선 → 커밋 → 학습  개선이 누적된다
```

v1은 이 그림에서 **문 하나**를 만들었다. v2는 **한 바퀴**를 만든다.

## 무엇을 만들고 무엇을 안 만드는가

필요한 조각은 이미 생태계에 대부분 있다. 없는 것은 **언제 · 어떤 순서로 ·
무엇을 부를 것인가** 하나다. 그래서 fe-harness는 도구가 아니라 **배선**이다.

소유하는 것은 셋뿐이다.

| | 구현 |
| --- | --- |
| **역할 정의** — 도구는 자기가 루프의 어느 칸인지 모른다 | `.fe-harness.json`의 `roles` |
| **트리거** — 기억해서 부르는 건 결국 안 부른다 | 훅 |
| **누적과 승격** — 반복된 지적을 규칙으로 올리는 판단 | `findings.md` |

**만들지 않는 것:** 좋은 코드의 정의, 리뷰 실행, 린터·타입체커, 중복 탐지기,
커밋 메시지 작성기, 규칙 자동 추가(제안까지만).

## 설치

끼울 도구들이 사는 마켓플레이스를 **먼저** 등록해야 한다. 등록하지 않으면
의존성이 해결되지 않아 `dependency-unsatisfied`로 플러그인이 비활성화된다.

```bash
# 1. 의존 마켓플레이스 (먼저)
claude plugin marketplace add toss/frontend-fundamentals
claude plugin marketplace add anthropics/claude-plugins-official

# 2. fe-harness
claude plugin marketplace add <이 저장소 경로 또는 URL>
claude plugin install fe-harness@fe-harness
```

의존 플러그인은 **자동으로 함께 설치된다.** 다만 한 번에 다 해결되지 않는
경우가 있는데, 그때는 에러 메시지가 빠진 것을 정확히 알려준다.

설치 후 **반드시 확인한다**:

```bash
claude plugin list      # Status 가 실패가 아닌지
```

`claude plugin validate --strict` 통과와 로드 성공은 별개다. 매니페스트가
멀쩡해도 훅이 하나도 안 붙어 있을 수 있다.

### 무엇을 요구하는가

| 플러그인 | 역할 |
| --- | --- |
| `frontend-fundamentals@toss` | **review** · **guide** — 응집도·결합도·예측가능성·가독성 |
| `hookify@claude-plugins-official` | **learn** — 반복된 지적을 규칙으로 승격 |
| `commit-commands@claude-plugins-official` | **record** — 커밋·PR 워크플로 |

**기본 설정이 이름을 부르는 것은 전부 필수다.** 하나라도 없으면 fe-harness가
비활성화된다 — 기본값이 부르는데 없으면 그 역할이 조용히 비고, 그건 도는
척하는 것이기 때문이다.

`refine` 역할은 Claude Code 내장 `simplify`를 쓰므로 설치할 것이 없다.

## 쓰는 법

```
/lap           커밋 직전 — 빠른 내부 루프 (이 커밋의 diff 만)
/lap push      푸시 직전 — 비싼 외부 루프 (브랜치 전체)
```

**한 바퀴가 한 번의 개선이다.**

| | 내부 루프 (`/lap`) | 외부 루프 (`/lap push`) |
| --- | --- | --- |
| 대상 | 이번 커밋의 diff | 브랜치 전체 |
| 중복·죽은 코드 | **델타** — 이번에 늘었는가 | **전체 스캔** |
| 리뷰 범위 | `HEAD` | `main...HEAD` |
| 승격 제안 | 안 함 | **함** |

**외부 루프가 내부 루프의 구조적 한계를 메운다.** 델타 검사는 커밋 A와 커밋 C
사이에 생긴 중복을 못 본다 — 각 커밋 시점에는 증가가 없기 때문이다.

지적은 `.fe-harness/findings.md`에 쌓이고, **같은 카테고리가 3회 반복되면 규칙으로
승격을 제안**한다. 그게 루프가 도는 증거다.

**이 파일은 커밋하는 것을 권한다.** 3회 카운트가 세션을 넘어 누적돼야 하고,
"커밋당 신규 지적 수가 줄어드는가"가 이 도구가 작동하는지 아는 유일한 지표라
히스토리가 남아야 한다. 로컬에만 두고 싶으면 `.gitignore`에 `.fe-harness/`를
추가하면 되지만, 그러면 팀이 같은 지적을 각자 3번씩 받게 된다.

## 지금 도는 훅

| 훅 | 시점 | 동작 |
| --- | --- | --- |
| 포맷 | `Write`/`Edit` 후 | 편집된 파일 1개만 포맷 |
| 린트 피드백 | `Write`/`Edit` 후 | `--fix` 후 남은 문제를 **그 턴 안에** 알림 |
| 컴포넌트 신호 | `Write`/`Edit` 후 | 한 파일에 컴포넌트가 여럿이면 **경고** (차단 아님) |
| 분량 게이트 | `Write`/`Edit` 전 | 임계값 초과 시 **반려** |
| 품질 게이트 | 턴 종료 시 | 타입체크·테스트 실패면 **종료 차단** |
| 지침 주입 | 세션 시작 | 임계값을 컨텍스트에 한 줄로 |

**포맷이 왜 필요한가** — Claude가 `Write`로 만든 파일은 에디터의 저장 이벤트를
안 거친다. format-on-save가 걸려 있어도 적용되지 않는다.

**린트가 왜 품질 향상인가** — 타입 에러와 lint 에러는 취향이 아니라 **틀린
코드**다. 그리고 Claude는 자기가 방금 만든 걸 그 자리에서 못 본다.
`PostToolUse`의 stderr는 그 턴 안에서 간다 — 피드백이 분에서 초로 줄어든다.

**컴포넌트 개수는 왜 차단이 아닌가** — 셀 수 있지만 그 개수가 문제인지는
읽어야 안다. 아이콘 래퍼 27개를 모은 배럴 파일은 정상이다. 판단은 review가 한다.

## 설정

프로젝트 루트에 `.fe-harness.json`을 두면 **추론 없이 무조건 신뢰한다.**
없으면 추론하고, 추론도 실패하면 **조용히 통과한다.** 확신 없이 뭔가 실행해서
개발을 막는 것보다 아무것도 안 하는 게 낫다.

전체 예시는 [`.fe-harness.example.json`](.fe-harness.example.json).

```json
{
  "roles": {
    "guide":  ["frontend-fundamentals:readability", "frontend-fundamentals:cohesion"],
    "review": "frontend-fundamentals:reviewer",
    "refine": "simplify",
    "record": "commit-commands:commit",
    "learn":  "hookify"
  },
  "verify": {
    "lint": "",
    "typecheck": "pnpm typecheck",
    "test": "",
    "duplication": "npx jscpd --min-lines 8 --reporters json --silent",
    "deadcode": "npx knip --reporter json"
  },
  "signals": { "maxNewFileLines": 250, "maxEditLines": 80, "maxComponentsPerFile": 1 }
}
```

**역할 값 문법**

```
"이름"       그대로 부른다. plugin:agent · plugin:skill · skill · /command
["a","b"]   여럿. review 만 병렬, 나머지는 순서대로
""          그 역할 끄기
키 없음      추론한다. 실패하면 조용히 통과
```

**해석은 모델이 한다.** 훅(셸)은 `frontend-fundamentals:reviewer`가 에이전트인지
스킬인지 모른다. 훅은 트리거와 이름 전달까지만 하고, 무엇으로 부를지는 `/lap`을
읽는 모델이 정한다. 이게 하드 의존성을 없애는 지점이다.

**`verify`는 추론하지 않는다.** `format`과 `lint`만 prettier / eslint / biome를
추론한다. `typecheck` · `test` · `duplication` · `deadcode`는 **명시했을 때만**
돈다 — 차단하는 검사가 확신 없이 추론한 명령으로 개발을 막으면 안 되고,
추론한 `test`가 몇 분짜리일 수도 있다.

### 끄는 법

방해되면 끈다. **끌 방법이 없는 도구는 결국 삭제된다.**

```json
{ "disable": { "signals": true } }
```

| 키 | 무엇 |
| --- | --- |
| `guide` | 세션 시작 지침 주입 |
| `format` | 포맷 |
| `lint` | 린트 피드백 |
| `gate` | 품질 게이트 (`Stop`) |
| `verify` | 중복·죽은 코드 측정 |
| `signals` | 분량 게이트 · 컴포넌트 경고 |

`jq`가 없으면 플러그인 전체가 no-op이 된다.

### `guidance`

리뷰·신호 메시지 끝에 그대로 덧붙는 한 줄이다. 이 저장소만의 맥락을 여기 둔다.

```json
{ "guidance": "쪼개기 전에 이 저장소의 컴포넌트 배치 규칙을 확인할 것" }
```

## 임계값의 근거

기본값은 감이 아니라 실측이다. 현업 저장소 5개에서 파일 생성 8,467건,
수정 24,976건을 쟀다 ([`tools/measure-thresholds.sh`](tools/measure-thresholds.sh)로 재현 가능).

| | p50 | p90 | p95 | p99 |
| --- | --- | --- | --- | --- |
| 파일이 처음 만들어질 때의 크기 | 49 | 174 | **244** | 437 |
| 수정 커밋에서 추가된 줄 수 | 4 | 33 | **59** | 163 |

`maxNewFileLines: 250`은 p95에 앉는다. `maxEditLines: 80`은 p96~97이다.

**측정 대상을 고르는 게 절반이었다.** 현재 파일 크기를 재면 안 된다 — 600줄
파일은 처음부터 600줄로 태어나지 않는다.

**저장소마다 분포가 다르다** — 생성 시 중앙값이 37~65로 갈렸다.
직접 재고 조정하는 걸 권한다.

```bash
tools/measure-thresholds.sh /path/to/your-repo
```

## 설계 판단

**왜 커밋이 루프의 경계인가**
한 가지 일이 끝나는 지점이고, diff가 확정되고, 사람이 이미 멈추는 곳이다.
턴 단위는 경계가 아니다 — 오타 수정 턴과 리팩터링 턴에 같은 기준을 댈 수 없다.

**왜 중복은 리뷰가 아니라 CLI인가**
중복과 죽은 코드는 셀 수 있고 **동시에** "틀렸다"고 단정할 수 있다. 에이전트에게
시키면 부정확하고 토큰이 비싸다. 반대로 "이 이름이 하는 일과 맞나"를 정규식으로
재려 하면 v1의 실수를 반복한다.

**왜 `0`과 "못 쟀다"를 구분하는가**
섞으면 도구가 죽었을 때 "중복이 사라졌다"고 보고하게 된다.
**훅이 낼 수 있는 최악의 출력은 차단이 아니라 거짓말이다.**

**왜 개선을 자동 적용하지 않는가**
이미 커밋된 코드를 바꾸면 fixup 커밋이 생기고, 잘못 고쳤을 때 되돌리기가
번거롭다. 무엇보다 지적이 쓸모 있는지 아직 모른다.

**왜 반려 메시지에 끄는 방법을 안 적는가**
그 메시지는 사람이 아니라 Claude가 읽는다. 끄는 법을 알려주면 게이트를 끄는
쪽으로 갈 수 있다. 그래서 README에만 적는다.

## 알려진 한계

- **자동 트리거가 아직 없다.** 지금은 `/lap`을 직접 불러야 한다.
- **`learn`의 실사용 기록이 없다.** 동작은 검증했지만 3회라는 임계값과
  카테고리 목록이 실제로 맞는지는 아직 관찰되지 않았다.
- **같은 컴포넌트를 감싸기만 한 경우도 2개로 센다.**
  `const Base = forwardRef(...)` 뒤에 `export const X = memo(Base)`. 오탐이다.
- **클래스 컴포넌트 미지원** (`class Foo extends Component`).
- **한 턴 전체의 변경량은 보지 않는다.** 240줄짜리 파일 10개는 전부 통과한다.
  적절한 턴 크기는 작업 종류마다 달라서 임계값이 존재할 수 없다고 판단했다.
- **`jq` 의존.** 없으면 전체 no-op.
- **Windows는 WSL 기준으로만 확인.** macOS 기본 bash 3.2에 맞춰 작성했다.
- **eval 하니스 없음.** 문구와 임계값이 실제로 효과가 있는지는 아직 재현 가능한
  방식으로 측정되지 않았다.

## 개발

```bash
./test.sh                      # 회귀 테스트
claude plugin validate . --strict
```

훅을 직접 실행하는 게 디버깅에 제일 빠르다:

```bash
echo '{"tool_name":"Write","cwd":"'$PWD'","tool_input":{"file_path":"/tmp/a.tsx","content":"x"}}' \
  | ./hooks/scripts/guard-size.sh; echo "exit=$?"
```

설계 문서: [docs/DESIGN.md](docs/DESIGN.md) ·
v1과 그 폐기 근거: [docs/DESIGN-v1.md](docs/DESIGN-v1.md) ·
그 과정의 회고: [docs/RETROSPECTIVE.md](docs/RETROSPECTIVE.md)

## 라이선스

MIT. [LICENSE](LICENSE) 참조.
