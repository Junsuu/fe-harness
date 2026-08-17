// 기대: components = 2
// 증상 ⑤ — 재사용하지도 않을 컴포넌트를 파일 안에 인라인으로 만든 경우.
// P0-3 이 반려해야 하는 형태.
import type { ReactNode } from 'react';

function EmptyState({ message }: { message: string }) {
  return <p role="status">{message}</p>;
}

export function OrderList({ orders }: { orders: ReactNode[] }) {
  if (orders.length === 0) {
    return <EmptyState message="주문이 없습니다" />;
  }

  return <ul>{orders}</ul>;
}
