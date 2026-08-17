// 기대: components = 2
// memo / forwardRef. `forwardRef\(` 로 쓰면 제네릭이 낀 형태를 놓친다 → `forwardRef\b`.
import { forwardRef, memo } from 'react';

import { BaseCard } from './base-card';
import type { InputProps } from './types';

export const Card = memo(BaseCard);

export const Input = forwardRef<HTMLInputElement, InputProps>((props, ref) => (
  <input ref={ref} {...props} />
));
