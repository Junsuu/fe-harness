// 기대: components = 4
// const 할당 형태 4종. 타입 애노테이션(`: React.FC<Props>`)이 껴 있어도 잡아야 한다.
import type { FC, ReactNode } from 'react';

interface PanelProps {
  children: ReactNode;
}

const Chip = () => <span />;

const Panel: FC<PanelProps> = ({ children }) => <section>{children}</section>;

const Row = props => <div>{props.label}</div>;

const Loader = async () => {
  const data = await Promise.resolve(null);
  return <div>{String(data)}</div>;
};

export { Chip, Loader, Panel, Row };
