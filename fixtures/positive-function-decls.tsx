// 기대: components = 4
// function 선언 형태 4종. 제네릭 컴포넌트는 `(` 가 아니라 `<` 로 이어진다.

function Badge() {
  return <span className="badge" />;
}

export function Card() {
  return <div className="card" />;
}

export default function Page() {
  return <main />;
}

export function List<T>(props: { items: T[] }) {
  return <ul>{props.items.length}</ul>;
}
