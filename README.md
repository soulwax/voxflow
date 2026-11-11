# voxflow

Pure Dart visual node graph, memoized reactive dataflow evaluator, and event-driven Blueprint exec runtime. Zero external runtime dependencies.

## Features

- **Strongly Typed Sockets (`PinType`)**: `exec`, `boolVal`, `intVal`, `floatVal`, `vec2Val`, `vec3Val`, `stringVal`, `colorVal`, `any` with safe implicit coercion rules (`int <-> float`, any -> `string`).
- **Dual Execution Models**:
  - **Memoized Pull Dataflow (`DataflowEvaluator`)**: Topological / lazy evaluation with cycle detection and variable-write cache invalidation.
  - **Event & Latent Blueprint Execution (`FlowRunner`)**: `OnStart`, `OnUpdate(dt)`, custom `OnEvent`, `Branch`, `Sequence`, `ForLoop`, `DoOnce`, and non-blocking latent `Delay` timers.
- **Rich Standard Node Library (`StandardNodes`)**: Math, trigonometry, logic/comparison, 2D/3D vector math, colors, blackboard variables, subgraphs/macros, signals, and debug print logs.
- **Cycle Detection & Topological Sorting (`FlowGraph`)**: Kahn's algorithm DAG validation + JSON round-trip serialization preserving node canvas layout positions, literal pin overrides, and blackboard defaults.
