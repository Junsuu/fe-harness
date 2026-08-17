// 기대: flag-props = "ToggleCardProps (boolean prop 3개)"
// 증상 ④ — option flag props. 콜백 인자의 boolean 은 세면 안 된다.
import type { ReactNode } from 'react';

export interface ToggleCardProps {
  title: string;
  disabled: boolean;
  loading?: boolean;
  compact: boolean;
  onToggle: (next: boolean) => void;
  render?: (open: boolean) => ReactNode;
}

export function ToggleCard({ title }: ToggleCardProps) {
  return <div>{title}</div>;
}
