// 기대: flag-props = (출력 없음)
// boolean 이 1개뿐이고 나머지는 콜백 인자다. 여기서 경고가 나오면 오탐.
import type { ReactNode } from 'react';

export interface DrawerProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  renderHeader?: (collapsed: boolean) => ReactNode;
  children: ReactNode;
}

export function Drawer({ children }: DrawerProps) {
  return <aside>{children}</aside>;
}
