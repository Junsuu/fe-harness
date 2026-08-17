// 기대: components = 4
// const 할당 형태 4종. 타입 애노테이션(`: React.FC<Props>`)이 껴 있어도 잡아야 한다.
import type { FC, ReactNode } from 'react';

interface PanelProps {
  children: ReactNode;
}

const Chip = () => <span />;

const Panel: FC<PanelProps> = ({ children }) => <section>{children}</section>;

// 괄호 없는 단일 인자 분기를 검증하는 줄이다. Prettier 는 arrowParens 기본값이
// "always" 라 이걸 `(props) =>` 로 바꿔버리고, 그러면 이 분기가 테스트되지 않는다.
// prettier-ignore
const Row = props => <div>{props.label}</div>;

const Loader = async () => {
  const data = await Promise.resolve(null);
  return <div>{String(data)}</div>;
};

export { Chip, Loader, Panel, Row };
