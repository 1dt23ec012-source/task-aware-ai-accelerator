<div align="center">

# Task-Aware Object Selection AI Hardware Accelerator

### **AXI4 Edge-AI Inference IP | Artix-7 FPGA Prototyping | SKY130A GDSII Hardening**
**Contests:** DVCon India 2026 Design Contest (Team Vulcan 629) & VLSID 2027 Tape-Out Contest  
**Host Architecture:** C-DAC VEGA RISC-V SoC

[![Artix-7 FPGA](https://img.shields.io/badge/FPGA-Artix--7%20(XC7A35T)-purple?style=for-the-badge&logo=amd&logoColor=white)](https://github.com/1dt23ec012-source/task-aware-ai-accelerator-sky130)
[![SKY130A ASIC](https://img.shields.io/badge/ASIC%20GDSII-SkyWater%20130nm-blue?style=for-the-badge)](https://github.com/1dt23ec012-source/task-aware-ai-accelerator-sky130)
[![Timing Closed](https://img.shields.io/badge/STA-50%20MHz%20Timing%20Met%20(%2B2.475ns%20WNS)-brightgreen?style=for-the-badge)](https://github.com/1dt23ec012-source/task-aware-ai-accelerator-sky130)
[![DRC/LVS Clean](https://img.shields.io/badge/Sign--Off-DRC%20%2F%20LVS%20Clean-success?style=for-the-badge)](https://github.com/1dt23ec012-source/task-aware-ai-accelerator-sky130)

</div>

---

## 📖 Executive Summary

Conventional edge object detection networks (YOLO, SSD, Faster R-CNN) detect and localize all objects in a visual scene indiscriminately. When deployed in task-driven robotic systems where physical actions are prompted by natural language instructions, this task-agnostic approach causes high memory bandwidth overhead, redundant CPU processing, and slow decision latency.

This project implements an **AXI4-compliant Task-Aware Object Selection Hardware Accelerator IP**. The accelerator fuses prompt text embeddings with candidate visual vectors, computes signed Q1.15 affordance compatibility scores, applies dynamic 2-bit semantic context rules, and ranks candidates through an ultra-low-latency **5-stage parallel tournament reduction tree**.

The core was verified in simulation, validated on physical **Artix-7 FPGA silicon** with live JTAG Virtual I/O, and hardened to a clean **GDSII layout in SkyWater SKY130A** using the open-source LibreLane/OpenROAD flow.

---

## 🏛️ Microarchitecture Specification

```text
                        ┌────────────────────────────────────────────────────────────┐
                        │             AXI4 Master DMA Burst Engine (64-bit)          │
                        └─────────────────────────────┬──────────────────────────────┘
                                                      │ 64-bit Vector Beats
                                                      ▼
┌──────────────────┐    MMIO Regs       ┌─────────────────────────────┐
│  AXI4-Lite Slave ├───────────────────►│  Synchronous Input Buffer   │ (1024 × 64-bit BRAM)
│  (0x20060000)    │                    └─────────────┬───────────────┘
└──────────────────┘                                  │ Q1.15 Embeddings
                                                      ▼
                                        ┌─────────────────────────────┐
                                        │  Pipelined DSP48E1 MAC Unit │ (3-Stage Dot Product)
                                        └─────────────┬───────────────┘
                                                      │ Raw Affordance Scores
                                                      ▼
                                        ┌─────────────────────────────┐
                                        │   Context Reasoning Engine  │ (2-Bit Semantic Reweighting)
                                        └─────────────┬───────────────┘
                                                      │ Reweighted Scores
                                                      ▼
                                        ┌─────────────────────────────┐
                                        │   Parallel Rejection Gate   │ (Threshold Comparison)
                                        └─────────────┬───────────────┘
                                                      │ Filtered Candidates
                                                      ▼
                                        ┌─────────────────────────────┐
                                        │  5-Stage Tournament Tree    │ O(log₂ N) Parallel Sorter
                                        └─────────────┬───────────────┘
                                                      │ Winner ID & Score
                                                      ▼
                                        ┌─────────────────────────────┐
                                        │  Output BRAM & Interrupt Gen│ Magic: 0x44564330
                                        └─────────────────────────────┘
