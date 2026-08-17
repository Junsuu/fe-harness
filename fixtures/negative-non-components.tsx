// 기대: components = 0
// 컴포넌트처럼 보이지만 아닌 것들. `const [A-Z]` 만으로 세면 전부 오탐된다.
import styled from '@emotion/styled';
import { z } from 'zod';

import { ApiClient } from './api-client';

const MAX_ITEMS = 20;
const DEFAULT_TIMEOUT_MS = 3_000;

const ROUTES = {
  home: '/',
  detail: (id: string) => `/items/${id}`,
};

const Client = new ApiClient({ baseUrl: '/api' });

const ItemSchema = z.object({
  id: z.string(),
  name: z.string(),
});

const Wrapper = styled.div`
  display: flex;
`;

const Inner = styled(Wrapper)`
  gap: 8px;
`;

const Button = styled.button({
  border: 'none',
});

function formatPrice(value: number) {
  return value.toLocaleString();
}

const toSlug = (value: string) => value.trim().toLowerCase();

type ItemDto = {
  id: string;
};

interface ItemView {
  id: string;
}

export { Button, Client, DEFAULT_TIMEOUT_MS, formatPrice, Inner, ItemSchema, MAX_ITEMS, ROUTES, toSlug, Wrapper };
export type { ItemDto, ItemView };
