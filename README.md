# 🔢 MOD-12 Loadable Up/Down Counter – SystemVerilog Testbench Verification

This project implements the **verification** of a MOD-12 (0 to 11) Loadable Up/Down Counter using a **modular SystemVerilog testbench**. 
The counter supports synchronous load, directional counting (up/down), and reset functionality. The testbench is built from scratch using a 
layered architecture inspired by UVM concepts, verified using **Siemens QuestaSim**.

---

## 📘 Project Overview

- **Design Type**: MOD-12 Loadable Up/Down Counter
- **HVL**: SystemVerilog
- **EDA Tool**: Siemens QuestaSim
- **Verification Type**: Constrained-Random with Functional Coverage

---

## 🧠 Features

### ✅ DUT Functionality
- **MOD-12 counter**: 4-bit counter that wraps from 11 → 0 or 0 → 11
- **Up/Down Counting**: Controlled by `up_down` signal
- **Synchronous Load**: Load any value between 0–11 via `load` signal
- **Synchronous Reset**: Active-high reset clears counter to 0

### ✅ Testbench Architecture
- **Generator**: Produces random and directed test vectors
- **Driver**: Drives DUT inputs
- **Monitor**: Captures DUT inputs and outputs
- **Scoreboard**: Compares DUT output with expected behavior
- **Coverage**: Functional coverage for all operation modes
