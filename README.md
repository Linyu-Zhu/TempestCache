# TempestCache
TempestCache: Adaptive Cache Intelligence for the Modern Data Storm

##### A Lightweight, Pattern-Aware Cache Framework with Coordinated Hot Data Management
**TempestCache** is a lightweight, pattern-aware cache optimization framework for modern multi-core systems. It integrates frequency decay, pattern detection, and prefetch-LRU coordination for adaptive memory management.

![logo](assets/logo.png)

## 🔍 Key Features

- **Time-decayed frequency tracking** using Q4.4 fixed-point arithmetic
- **Access pattern classification** (Hot / Periodic / Normal) with just 4–8 history entries
- **Temporary-Hot (T-H) tagging** for coordinated prefetch and replacement
- **Multi-bank memory support** for scalable cache partitioning

## 🔍 Evaluation
The baseline is the same port Cache.
Testbench设计如下：
1.按照Dcache port实例化tb_dcache.2.接入一个内存模型,用来模拟delay.
3.



## 🏗 Code Structure

```bash
TempestCache/
├── vivado/    
    ├── dcache_1/             # Verilog/SystemVerilog modules
        ├── sim/
            ├── memory_model.sv
            ├── tb_dcache.sv
        ├── src/
           ├── dcache.sv




