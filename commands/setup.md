---
description: 이 저장소에 맞는 .fe-harness.json 을 만든다. 설치 후 한 번만.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/hooks/scripts/detect-project.sh:*), Bash(git ls-files:*), Read, Write, Edit, Grep, Glob
---

## 하는 일

저장소를 훑어 `.fe-harness.json` 을 만든다.

**설정이 없어도 루프는 돈다.** `review` 는 기본값으로 돌고 `lint`·`format` 은
추론된다. 이 커맨드는 필수가 아니라 **`verify` 를 채워 넣는 작업**이다 —
타입체크 · 테스트 · 중복 · 죽은 코드는 명시해야만 돌기 때문이다.

---

## 1 · 사실을 모은다

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/detect-project.sh
```

한 번에 다 나온다. `package.json` 을 따로 읽지 않는다.

`existingConfig` 가 `true` 면 **덮어쓰기 전에 반드시 물어본다.** 기존 설정에
사람이 손으로 조정한 값이 들어 있을 수 있다.

---

## 2 · 사실로 정해지는 것은 묻지 않는다

| 설정 | 판정 |
| --- | --- |
| `verify.lint` · `verify.format` | **비워 둔다.** 린터 설정이 있으면 플러그인이 알아서 추론한다 |
| `verify.deadcode` | `available.knip` 이 `true` 면 `npx knip --reporter json` |
| `verify.a11yRuntime` | 아래 3번 |
| `roles.*` | 기본값 그대로 둔다. 사용자가 다른 도구를 원한다고 말하지 않았다면 건드리지 않는다 |
| `exclude` | 생성 코드 · 스토리 · 테스트 파일 경로가 실제로 있으면 넣는다 |

`monorepo` 가 `true` 면 `guidance` 에 그 사실을 한 줄 남긴다. 루트에서 린터가
안 도는 저장소가 있어서 나중에 진단할 때 단서가 된다.

---

## 3 · 판단이 필요한 것만 묻는다

**한 번에 하나씩 묻지 말고 모아서 묻는다.** 설치 직후 한 번 쓰는 커맨드다.

### 타입체크

`scripts` 에서 후보를 고른다 (`typecheck` · `type-check` · `tsc` · `types`).
하나뿐이고 이름이 명확하면 **그대로 쓰고 알리기만 한다.** 여럿이거나 애매하면 묻는다.

`typescript` 가 `false` 면 건너뛴다.

### 테스트 — 반드시 확인받는다

**이름만 보고 넣지 않는다.** `Stop` 게이트는 턴이 끝날 때마다 돈다.
몇 분짜리 e2e 를 넣으면 매 턴이 몇 분씩 늘어나고, 그러면 사용자는 플러그인을 끈다.

이렇게 묻는다:

> `scripts.test` 는 `vitest run` 입니다. 턴이 끝날 때마다 돌려도 될 만큼 빠릅니까?
> 몇 초 안에 끝나면 넣고, 그보다 오래 걸리면 비워 두는 게 낫습니다.

**모르겠다고 하면 비워 둔다.** 안 도는 것보다 매 턴을 잡아먹는 게 나쁘다.

### 중복 검사

`available.jscpd` 가 `false` 면 `npx` 로 받아 쓸 수 있지만 첫 실행이 느리다.

> 중복 검사(`jscpd`)가 설치돼 있지 않습니다. `npx` 로 받아 쓸 수 있는데
> 첫 실행에 시간이 걸립니다. 넣을까요, 나중에 직접 설치한 뒤 켤까요?

`true` 면 묻지 않고 `npx jscpd --min-lines 8 --reporters json --silent` 를 넣는다.

### a11y 런타임 — 렌더 수단이 있을 때만

`render` 에 `true` 가 하나도 없으면 **묻지 않고 비워 둔다.**
스토리북이나 E2E 를 새로 만들라고 요구하지 않는다.

있으면 우선순위대로 제안한다: **E2E 안의 axe > 컴포넌트 테스트 안의 axe >
Storybook > 라우트 목록.** 이미 있는 수단에 얹는 것이지 새로 만드는 게 아니다.

### a11y 정적 검사

`jsx` 가 `true` 이고 `a11yPlugin` 이 `false` 면 제안한다. **이건 설정 파일이
아니라 저장소의 ESLint 설정에 들어간다.**

> `eslint-plugin-jsx-a11y` 가 없습니다. `alt` 누락 · 잘못된 role · label 미연결을
> 작성 직후에 잡아 줍니다. 기존 CI 를 깨지 않도록 `warn` 으로 추가할까요?

거절하면 다시 묻지 않는다.

---

## 4 · 쓴다

`.fe-harness.json` 을 만든다. **비운 항목에는 왜 비웠는지 주석(`__키`)을 남긴다.**
나중에 "이건 왜 안 도나" 하고 볼 때 답이 파일 안에 있어야 한다.

```json
{
  "verify": {
    "__test": "e2e 라 Stop 게이트에 넣지 않았다. 단위 테스트가 생기면 그때 채운다.",
    "test": ""
  }
}
```

**`roles` 는 사용자가 바꾸자고 하지 않았으면 아예 쓰지 않는다.** 기본값과 같은
값을 적어두면 "이걸 꼭 써야 하나"로 읽히고, 나중에 기본값이 바뀌어도 안 따라간다.

---

## 5 · 무엇이 켜졌고 무엇이 안 켜졌는지 알린다

표로 한 번에 보여준다. **비운 것은 이유까지 적는다.**

```
verify.lint         추론      eslint.config.mjs 를 찾았다
verify.typecheck    tsc --noEmit
verify.test         안 켬     e2e 라 매 턴 돌리기엔 무겁다
verify.duplication  안 켬     jscpd 미설치. 설치 후 켜면 된다
verify.deadcode     npx knip --reporter json
verify.a11yRuntime  안 켬     렌더 수단 없음
```

그리고 마지막에 한 줄:

> 커밋하면 루프가 자동으로 돕니다. 직접 돌리려면 `/lap` 입니다.
