# 操作系统实验一：PintOS 线程管理

## 实验概述

本实验基于 **PintOS** 教学操作系统，在已有的最小化线程系统基础上，完成三项核心任务：

| 任务 | 内容 | 测试分值占比 |
|------|------|------|
| Task 1 | Alarm Clock（定时器睡眠） | 20% |
| Task 2 | Priority Scheduling（优先级调度与捐赠） | 40% |
| Task 3 | Advanced Scheduler（4.4BSD 多级反馈队列） | 40% |

此外需完成**设计文档**（`doc/threads.tmpl`）。

**参考资料**: [Stanford CS140 PintOS Lab1](https://web.stanford.edu/class/cs140/projects/pintos/pintos_1.html)

---

## 环境说明

登录后，PintOS 源码位于 `/root/pintos/src/`，已配置好编译工具链（i386-elf-gcc、bochs 模拟器等）。

```
/root/pintos/src/
├── threads/       ← 本次实验主要修改目录
├── devices/       ← timer.c 需要修改
├── lib/           ← 辅助函数
├── utils/         ← pintos 启动脚本
├── tests/threads/ ← 测试用例
└── ...
```

### PintOS 项目一文件概览

```
src/threads/
├── init.c          ← 第 3 步执行 (main)
├── interrupt.c
├── intr-stubs.S
├── io.h
├── kernel.lds.S
├── loader.S        ← 第 1 步执行
├── malloc.c
├── palloc.c
├── pte.h
├── start.S         ← 第 2 步执行
├── switch.S
├── synch.c
├── thread.c
├── thread.h
└── vaddr.h
```

### 快速验证环境

```bash
cd /root/pintos/src/threads
make
pintos -v -k -T 60 --bochs -- -q run alarm-single
```

若能看到测试输出，环境正常。也可以使用 `--qemu` 代替 `--bochs`。

---

## Task 1：Alarm Clock

### 背景

`timer_sleep(int64_t ticks)` 的当前实现使用**忙等待**（busy-wait）：线程在循环中反复调用 `thread_yield()` 直到时间到期，这会浪费大量 CPU 资源。

```c
/* 当前的错误实现（devices/timer.c） */
void timer_sleep(int64_t ticks) {
    int64_t start = timer_ticks();
    ASSERT(intr_get_level() == INTR_ON);
    while (timer_elapsed(start) < ticks)
        thread_yield();  // ← 忙等待，需要替换
}
```

### 目标

将 `timer_sleep()` 改为**阻塞式**实现：线程睡眠后进入阻塞状态，到期时由计时器中断唤醒，期间不占用 CPU。

### 实现思路

1. 在 `struct thread`（`threads/thread.h`）中添加字段记录唤醒时刻（如 `int64_t wake_tick`）
2. 调用 `timer_sleep()` 时，计算唤醒时刻，将线程阻塞并加入等待队列
3. 在 `timer_interrupt()`（每个 tick 被调用一次）中，检查等待队列，唤醒到期的线程

### 需要修改的文件

- `devices/timer.c`：修改 `timer_sleep()`，更新 `timer_interrupt()`
- `threads/thread.h`：在 `struct thread` 中添加 `wake_tick` 字段
- `threads/thread.c`：初始化新字段

### 测试方法

```bash
cd /root/pintos/src/threads && make
cd build

# 运行所有 alarm 测试
pintos -v -k -T 60 --bochs -- -q run alarm-single
pintos -v -k -T 60 --bochs -- -q run alarm-multiple
pintos -v -k -T 60 --bochs -- -q run alarm-simultaneous
pintos -v -k -T 60 --bochs -- -q run alarm-priority
pintos -v -k -T 60 --bochs -- -q run alarm-zero
pintos -v -k -T 60 --bochs -- -q run alarm-negative
```

**预期结果**：每个测试输出 `PASS`。

### 注意事项

> ⚠️ 禁止在实现中出现任何形式的忙等待（循环调用 `thread_yield()`），否则该任务得 0 分。

---

## Task 2：Priority Scheduling（优先级调度与捐赠）

### 背景

PintOS 线程有优先级（`PRI_MIN=0` 至 `PRI_MAX=63`，默认 `PRI_DEFAULT=31`）。目前调度器**未实现**优先级抢占，需要完成：

1. **抢占式优先级调度**：高优先级线程就绪时，立即抢占当前线程
2. **优先级捐赠**：防止优先级反转（Priority Inversion）

### 优先级捐赠说明

当高优先级线程 H 等待低优先级线程 L 持有的锁时，H 将自己的优先级**捐赠**给 L，使 L 能尽快执行并释放锁。

- **多重捐赠**：线程可同时持有多个锁，需处理多个线程捐赠的情况
- **嵌套捐赠**：H 等 M 等 L → L 的优先级应提升至 H 的优先级（支持至少 8 层嵌套）
- **仅对 Lock 实现捐赠**（不需要对信号量和条件变量实现）

### 需要修改的文件

- `threads/thread.c` / `threads/thread.h`：调度逻辑、线程结构
- `threads/synch.c`：锁的获取/释放中加入优先级捐赠逻辑

### 关键函数

```c
/* 需要实现或修改 */
void thread_set_priority(int new_priority);  // 设置优先级，必要时立即让出CPU
int  thread_get_priority(void);              // 返回当前有效优先级（含捐赠）
```

### 测试方法

```bash
cd /root/pintos/src/threads && make
cd build

# 基础优先级测试
pintos -v -k -T 60 --bochs -- -q run priority-change
pintos -v -k -T 60 --bochs -- -q run priority-preempt
pintos -v -k -T 60 --bochs -- -q run priority-fifo

# 优先级捐赠测试
pintos -v -k -T 60 --bochs -- -q run priority-donate-one
pintos -v -k -T 60 --bochs -- -q run priority-donate-multiple
pintos -v -k -T 60 --bochs -- -q run priority-donate-multiple2
pintos -v -k -T 60 --bochs -- -q run priority-donate-nest
pintos -v -k -T 60 --bochs -- -q run priority-donate-chain
pintos -v -k -T 60 --bochs -- -q run priority-donate-sema
pintos -v -k -T 60 --bochs -- -q run priority-donate-lower

# 同步原语优先级测试
pintos -v -k -T 60 --bochs -- -q run priority-sema
pintos -v -k -T 60 --bochs -- -q run priority-condvar
```

### 常见问题

- 输出中出现**重复的测试名**：说明调度时机有误，检查抢占逻辑
- 死锁：检查禁用中断的区间是否过长

---

## Task 3：Advanced Scheduler（4.4BSD 多级反馈队列调度器）

### 背景

优先级调度可能导致低优先级线程**饥饿**（starvation）。4.4BSD 调度器通过动态调整优先级来解决这个问题。

使用 `-mlfqs` 参数启动时（设置 `thread_mlfqs = true`），调度器自动管理优先级，**忽略** `thread_set_priority()` 的调用和 `thread_create()` 的 priority 参数，也**不进行**优先级捐赠。

### 核心公式（使用 17.14 定点数）

```
每 4 个 tick 更新一次线程优先级:
  priority = PRI_MAX - (recent_cpu / 4) - (nice * 2)

每秒更新一次 recent_cpu:
  recent_cpu = (2 * load_avg) / (2 * load_avg + 1) * recent_cpu + nice

每秒更新一次 load_avg（系统平均就绪线程数）:
  load_avg = (59/60) * load_avg + (1/60) * ready_threads
```

### 定点数运算

由于 PintOS 不使用浮点数，需要自行实现定点数运算库：

```c
/* 创建新文件 threads/fixed-point.h（约 120 行） */
/* 使用 17.14 格式：最低 14 位为小数部分 */
#define F (1 << 14)

#define INT_TO_FP(n)         ((n) * (F))
#define FP_TO_INT_ZERO(x)    ((x) / (F))
#define FP_TO_INT_NEAREST(x) ((x) >= 0 ? ((x) + (F)/2) / (F) : ((x) - (F)/2) / (F))
#define ADD_FP(x, y)         ((x) + (y))
#define SUB_FP(x, y)         ((x) - (y))
#define MUL_FP(x, y)         ((int64_t)(x) * (y) / (F))
#define DIV_FP(x, y)         ((int64_t)(x) * (F) / (y))
#define ADD_FP_INT(x, n)     ((x) + (n) * (F))
#define SUB_FP_INT(x, n)     ((x) - (n) * (F))
#define MUL_FP_INT(x, n)     ((x) * (n))
#define DIV_FP_INT(x, n)     ((x) / (n))
```

### 需要修改的文件

- `threads/fixed-point.h`（新建）
- `threads/thread.c` / `threads/thread.h`：添加 `nice`、`recent_cpu` 字段，更新调度逻辑
- `devices/timer.c`：在 `timer_interrupt()` 中按时更新各值

### 测试方法

```bash
cd /root/pintos/src/threads && make
cd build

pintos -v -k -T 480 --bochs -- -q -mlfqs run mlfqs-load-1
pintos -v -k -T 480 --bochs -- -q -mlfqs run mlfqs-load-60
pintos -v -k -T 480 --bochs -- -q -mlfqs run mlfqs-load-avg
pintos -v -k -T 480 --bochs -- -q -mlfqs run mlfqs-recent-1
pintos -v -k -T 480 --bochs -- -q -mlfqs run mlfqs-fair-2
pintos -v -k -T 480 --bochs -- -q -mlfqs run mlfqs-fair-20
pintos -v -k -T 480 --bochs -- -q -mlfqs run mlfqs-nice-2
pintos -v -k -T 480 --bochs -- -q -mlfqs run mlfqs-nice-10
pintos -v -k -T 480 --bochs -- -q -mlfqs run mlfqs-block
```

> 注意：mlfqs 测试需要较长时间运行，因此超时参数设为 `-T 480`。

---

## 设计文档

完成实验后，需要填写设计文档模板 `doc/threads.tmpl`。

文档中需要回答每个任务的设计问题，包括：

- 数据结构设计
- 算法思路
- 同步策略
- 设计决策的理由

将填写好的文档（纯文本、Markdown 或 PDF 格式）提交到仓库中。

---

## 一键运行所有测试

```bash
cd /root/pintos/src/threads
make
make check
make grade
```

---

## 调试技巧

### 使用 GDB

`make check` 会输出每个测试对应的 `pintos` 命令。在命令中加入 `--gdb` 即可使用 GDB 调试。

例如：

```bash
# 终端 1：启动 pintos 并等待 GDB 连接
cd /root/pintos/src/threads/build
pintos --gdb -v -k -T 480 --bochs -- -q -mlfqs run mlfqs-load-60

# 终端 2：启动 GDB 并连接
cd /root/pintos/src/threads/build
pintos-gdb kernel.o
(gdb) target remote localhost:1234
(gdb) b main
(gdb) c
```

### 使用 printf

> ⚠️ `printf` 底层会调用 `lock_acquire` → `sema_down`。如果你的信号量/调度实现有 bug，`printf` 可能导致 kernel panic。此时请改用 GDB 调试。

### 使用 ASSERT

善用 `ASSERT()` 宏检查不变量，尽早发现错误。

---

## 提交要求

1. 修改后的源代码（`threads/` 和 `devices/` 目录）
2. 填写完整的设计文档（基于 `doc/threads.tmpl`）

---

## 参考资料

- [Stanford PintOS Lab1 文档](https://web.stanford.edu/class/cs140/projects/pintos/pintos_1.html)
- [PintOS 参考手册](https://web.stanford.edu/class/cs140/projects/pintos/pintos.pdf)
- [PintOS 4.4BSD 调度器说明](https://web.stanford.edu/class/cs140/projects/pintos/pintos_7.html#SEC131)

---

*祝实验顺利！遇到问题请善用 GDB 调试和 pintos 的 `-v` 详细输出模式。*
