// 기대: components = 1
// 정상 파일. 상수 · styled · 헬퍼 · 스키마가 섞여 있어도 컴포넌트는 하나다.
// 초기 버그: 이 파일이 5개로 나왔었다.
import styled from '@emotion/styled';

import { formatPrice } from './format';

const MAX_VISIBLE = 5;

const List = styled.ul`
  display: grid;
`;

const Empty = styled.li`
  color: gray;
`;

function toItemKey(id: string, index: number) {
  return `${id}-${index}`;
}

export interface PriceListProps {
  items: { id: string; price: number }[];
}

export function PriceList({ items }: PriceListProps) {
  const visible = items.slice(0, MAX_VISIBLE);

  if (visible.length === 0) {
    return (
      <List>
        <Empty>표시할 항목이 없습니다</Empty>
      </List>
    );
  }

  return (
    <List>
      {visible.map((item, index) => (
        <li key={toItemKey(item.id, index)}>{formatPrice(item.price)}</li>
      ))}
    </List>
  );
}
